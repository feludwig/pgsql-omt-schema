#!/usr/bin/python3

#  (c) This file is part of pgsql-omt-schema
#  see https://github.com/feludwig/pgsql-omt-schema for details
#  Author https://github.com/feludwig
#
#   LICENSE https://github.com/feludwig/pgsql-omt-schema/blob/main/LICENSE
#   GPL v3 in short :
#     Permissions of this strong copyleft license are conditioned on making available
#     complete source code of licensed works and modifications, which include larger
#     works using a licensed work, under the same license.
#     Copyright and license notices must be preserved.

import sys
import psycopg2
import os
import time
import threading
import queue
import typing
import statistics
printer_lock=threading.Lock()
make_cursor_lock=threading.Lock()

import run #local

format='pbf'


#maximally parallelize database: new connections only
def make_new_connection_cursor()->[psycopg2.extensions.connection,psycopg2.extensions.cursor] :
    for i in range(5) :
        try :
            with make_cursor_lock :
                access=psycopg2.connect(dbaccess)
                return access,access.cursor()
        except psycopg2.Error as err :
            # wait and retry to connect to database
            time.sleep(10)
    print('Timed out after 50s trying to connect to database')
    print(*access.notices,sep='\n')
    os._exit(1)

def gen_zxy_readinput()->typing.Iterator[[int,int,int]] :
    while True :
        try :
            line=input()
        except EOFError :
            #finished
            return
        try :
            z,x,y=line.split(' ')
        except ValueError as err :
            print('ERROR parsing line=',line)
            exit(1)
        yield (int(z),int(x),int(y))

def gen_zxy_range(z:str,x:str,y:str)->typing.Iterator[[int,int,int]] :
    zSpec=None
    if z.find(':')>=0 :
        #FORMAT zSpecified:zStart-zEnd with zSpecified<zStart<zEnd OR zSpecified:z
        zSpec,z=z.split(':')
        zSpec=int(zSpec)
    if z.find('-')>=0 :
        # z range, x and y are specified for starting zoom!
        zs=list(range(*map(int,z.split('-'))))
        zSpec=zs[0] if zSpec==None else zSpec
        #inclusive range
        zs.append(zs[-1]+1)
    else :
        zs=[int(z)]
        zSpec=zs[0] if zSpec==None else zSpec
    if x.find('-')>=0 :
        xs=list(range(*map(int,x.split('-'))))
        #inclusive range
        xs.append(xs[-1]+1)
    elif x=='*' :
        xs=list(range(2**zSpec))
    else :
        xs=[int(x)]
    if y.find('-')>=0 :
        ys=list(range(*map(int,y.split('-'))))
        #inclusive range
        ys.append(ys[-1]+1)
    elif y=='*' :
        ys=list(range(2**zSpec))
    else :
        ys=[int(y)]
    for z in zs :
        scale=2**(z-zSpec)
        for xr in xs :
            for x in range(xr*scale,(xr+1)*scale) :
                for yr in ys :
                    for y in range(yr*scale,(yr+1)*scale) :
                        yield (z,x,y)


class Writer(threading.Thread) :
    def __init__(self,get_access_new_cursor:typing.Callable[[],
            [psycopg2.extensions.connection,psycopg2.extensions.cursor]],
            query_to_run:str,with_landarea_stats=True) :
        threading.Thread.__init__(self)
        self.get_access_new_cursor=get_access_new_cursor
        self.access,self.c=self.get_access_new_cursor()
        self.finished=False
        self.query=query_to_run
        self.function_returns_stats=self.query.find('stats')>=0
        self.multiply_mogrify_args=self.query.count('%s')//3
        self.todo=queue.Queue(maxsize=0) #infinite size
        self.with_landarea_stats=with_landarea_stats
    def set_zooms(self,zs) :
        self.total_written={z:0 for z in zs}
        self.total_count={z:0 for z in zs}
        self.per_layer_stats={z:{} for z in zs}
        self.stats={z:{'size':[],'time':[],'landarea_size':[],'landarea_time':[]} for z in zs}
    def add_layer_stats_line(self,z,line:dict,weight=-1.0) :
        """ Where landarea_weight is the proportional land area
        of the entire tile, eg. 5/18/10 is poland only land (no ocean): weight=1.0
        and 5/15/10 is ireland+south UK weight=0.41
        """
        ln=line['name']
        if ln not in self.per_layer_stats[z] :
            self.per_layer_stats[z][ln]={'landarea':0.0,'count':0,'pcent':0.0,
                    'bytes':0,'landarea_bytes':0.0,
                    'rowcount':0,'landarea_rowcount':0.0}
        self.per_layer_stats[z][ln]['count']+=1
        self.per_layer_stats[z][ln]['pcent']+=float(line['pcent'])
        self.per_layer_stats[z][ln]['bytes']+=line['bytes']
        self.per_layer_stats[z][ln]['rowcount']+=line['rowcount']
        if self.with_landarea_stats and weight>1e-5 :
            self.per_layer_stats[z][ln]['landarea']+=weight
            self.per_layer_stats[z][ln]['landarea_bytes']+=line['bytes']/weight
            self.per_layer_stats[z][ln]['landarea_rowcount']+=line['rowcount']/weight

    def get_land_area_pcent(self,z:str,x:str,y:str)->float :
        water_tbl='water_polygons' if int(z)>8 else 'simplified_water_polygons'
        q=f'''WITH a(a) AS (SELECT ST_TileEnvelope(%s,%s,%s))
            SELECT greatest(0.0,1.0-(sum(ST_Area(ST_Intersection(way,a.a)))/ST_Area(a.a)))
            FROM {water_tbl},a WHERE ST_Intersects(way,a.a) GROUP BY(a.a);'''
        self.c.execute(self.c.mogrify(q,(z,x,y)))
        if self.c.rowcount==0 :
            return 1.0 #not even any intersection to water_polygons
        return self.c.fetchone()[0]

    @classmethod
    def print_layer_stats(cls,c:psycopg2.extensions.cursor,list_of_self,z) :
        """ Use database for pg_size_pretty...
        """
        def get_size_pretty(d:float) :
            c.execute(c.mogrify('SELECT pg_size_pretty(%s::numeric);',(d,)))
            return c.fetchone()[0]
        per_layer_stats={}
        per_z_stats={'time':[],'size':[],'landarea_time':[],'landarea_size':[]}
        w_l_a=list_of_self[0].with_landarea_stats
        #collect all data
        total_z_count=0
        total_z_landarea=0
        total_z_bytes=0
        for i in list_of_self :
            curr_landarea=0.0
            for k,v in i.per_layer_stats[z].items() :
                if k not in per_layer_stats :
                    per_layer_stats[k]=[0.0]*7
                for ix,field in enumerate(('landarea','count','pcent','bytes',
                        'landarea_bytes','rowcount','landarea_rowcount')) :
                    per_layer_stats[k][ix]+=v[field]
                if w_l_a :
                    curr_landarea=v['landarea']
            total_z_bytes+=i.total_written[z]
            total_z_count+=i.total_count[z]
            total_z_landarea+=curr_landarea
            for k in ('time','size','landarea_time','landarea_size'):
                per_z_stats[k].extend(i.stats[z][k])
        #sort
        if w_l_a :
            per_layer_stats_l=[(landarea_bytes,k,landarea,count,pcent,bytes,
                rowcount,landarea_rowcount)
                    for k,(landarea,count,pcent,bytes,landarea_bytes,
                        rowcount,landarea_rowcount) in per_layer_stats.items()]
            per_layer_stats={k:(landarea,count,pcent,bytes,landarea_bytes,
                rowcount,landarea_rowcount)
                    for (landarea_bytes,k,landarea,count,pcent,bytes,rowcount,
                        landarea_rowcount) in sorted(per_layer_stats_l,reverse=True)}
            #prepare print
            headers=['layer_name','avg_pcent','avg_landarea_bytes','avg_bytes','avg_landarea_rowcount','avg_rowcount']
            data=[(k,
                str(round(pcent/count,1)),
                get_size_pretty(round(landarea_bytes/count,1)),
                get_size_pretty(round(bytes/count,1)),
                str(round(landarea_rowcount/count)),
                str(round(rowcount/count)),
                ) for k,(landarea,count,pcent,bytes,landarea_bytes,
                    rowcount,landarea_rowcount) in per_layer_stats.items()]
        else :
            per_layer_stats_l=[(bytes,k,count,pcent,rowcount) for k,(landarea,count,
                    pcent,bytes,landarea_bytes,rowcount,landarea_rowcount) in per_layer_stats.items()]
            per_layer_stats={k:(count,pcent,bytes,rowcount) for (bytes,k,count,pcent,rowcount) in sorted(per_layer_stats_l,reverse=True)}
            #prepare print
            headers=['layer_name','avg_pcent','avg_bytes','avg_rowcount']
            data=[(k,
                str(round(v[1]/v[0],1)),
                get_size_pretty(round(v[2]/v[0],1)),str(round(v[3]/v[0])),
                ) for k,v in per_layer_stats.items()]
        p_insert=()
        if total_z_count==0 :
            print('ZeroDivisionError')
            return
        if w_l_a :
            p_insert=('avg_landarea',round(100*total_z_landarea/total_z_count,1),'%')
        #print
        print(f'z{z:02}',*p_insert,':')
        run.print_table(data,headers)

        print('total',round(total_z_bytes*1e-6,2),'MB, statistics for',total_z_count,'tiles :')
        #statistics
        rows={
            'time':lambda dgt,v:str(round(v,dgt))+'s/tile' if v!=None else '',
            'size':lambda dgt,v:get_size_pretty(round(v,dgt))+'/tile' if v!=None else '',
            'landarea_time':lambda dgt,v:str(round(v,dgt))+'s/landarea_tile' if v!=None else '',
            'landarea_size':lambda dgt,v:get_size_pretty(round(v,dgt))+'/landarea_tile' if v!=None else '',
        }
        if not w_l_a :
            rows.pop('landarea_time')
            rows.pop('landarea_size')
        stats_data=[]
        for r,get_fmt in rows.items() :
            data={}
            data['median']=(1,statistics.median(per_z_stats[r]))
            if len(per_z_stats[k])>=2 :
                data['stdev']=(2,statistics.stdev(per_z_stats[r]))
                data['1_pcent']=(0,statistics.quantiles(per_z_stats[r],n=100)[-1])
                data['1_pmil']=(0,statistics.quantiles(per_z_stats[r],n=1000)[-1])
            else :
                data['stdev']=(2,None)
                data['1_pcent']=(0,None)
                data['1_pmil']=(0,None)
            line=[r]
            line.extend([get_fmt(r_dgts,v) for d_f,(r_dgts,v) in data.items()])
            stats_data.append(line)
        run.print_table(stats_data,('sample type','median','stdev','1% worst','0.1% worst'))


    def run(self) :
        msg='Need to run .set_zooms before starting'
        assert hasattr(self,'total_count'),msg
        while True :
            z,x,y=self.todo.get(block=True)
            #check end sentinel
            if z==None :
                #but also check no more work to do
                if self.finished and self.todo.empty() :
                    break
                # else finish processing everything, but still keep sentinel in mind
                self.todo.put((None,None,None))
                continue # skip processing the None
            self.process(z,x,y)

    def join(self) :
        self.finished=True
        #end sentinel
        self.todo.put((None,None,None))
        threading.Thread.join(self)

    def print_notices(self) :
        notices_toprint=[]
        while len(self.access.notices)!=0 :
            notices_toprint.append(self.access.notices.pop(0))
        if len(notices_toprint)!=0 :
            with printer_lock :
                print('\t\t','\n\t\t'.join(notices_toprint))

    def process(self,z,x,y) :
        success=False
        for i in range(5) : #try again 5 times
            try :
                st_t=time.time()
                self.c.execute(self.c.mogrify(self.query,(z,x,y)*self.multiply_mogrify_args))
                success=True
                break
            # when function was redefined while running/did not exist when needed
            except psycopg2.Error as err :
                try :
                    self.c.execute('ABORT;')
                except psycopg2.Error as err2 :
                    #need to re-connect to database
                    self.access,self.c=self.get_access_new_cursor()
                with printer_lock :
                    print(f'{z:2}/{x}/{y}.{format}\t','failed SQL',repr(err),'retrying')
                self.print_notices()
        if not success :
            with printer_lock :
                print(f'{z:2}/{x}/{y}.{format}\t','retried 5 times, abandoning')
            return
        result=[dict(zip([col.name for col in self.c.description],i)) for i in self.c.fetchall()]

        weight=1.0
        print_additional=''
        if self.with_landarea_stats :
            weight=self.get_land_area_pcent(z,x,y)
            print_additional+=f'\t{weight*100:>5.1f}% landarea'
        if self.function_returns_stats :
            for line in result :
                if line['name']=='ALL' :
                    out_data=line['data']
                else :
                    self.add_layer_stats_line(z,line,weight)
        else :
            out_data=list(result[0].values())[0]

        tot_t=time.time()-st_t
        while True :
            dest_fn=f'{outdir}/{z}/{x}/{y}.{format}'
            try :
                if not os.path.exists(f'{outdir}/{z}/{x}') :
                    os.makedirs(f'{outdir}/{z}/{x}',exist_ok=True)
                with open(dest_fn,'wb') as f:
                    bs_written=f.write(out_data)
                break
            except PermissionError as err:
                input(f'{err}, press enter to retry:')
        self.total_written[z]+=bs_written
        self.total_count[z]+=1
        self.stats[z]['time'].append(tot_t)
        self.stats[z]['size'].append(bs_written)
        if self.with_landarea_stats and weight>1e-5:
            # if weight~=0, just don't sample...
            self.stats[z]['landarea_time'].append(tot_t/weight)
            self.stats[z]['landarea_size'].append(bs_written/weight)
        with printer_lock :
            displ_fn=f'{z:2}/{x}/{y}.{format}'
            print(f'{displ_fn:<20} {bs_written:>10} bytes {tot_t:>10.2f} s',print_additional)
        self.print_notices()

dbaccess,mode,outdir,*more=sys.argv[1:]
if mode=='--range' :
    z,x,*y=more
    y=y[0]
    tiles_generator=gen_zxy_range(z,x,y)
elif mode=='--list' :
    tiles_generator=gen_zxy_readinput()
else :
    print('unrecognized mode')
    exit(1)


query_to_run=f'SELECT * FROM omt_all_with_stats(%s,%s,%s);'
if '--contours' in more :
    query_to_run=f'SELECT * FROM contours_vector(%s,%s,%s);'
elif '--single' in more :
    layer_name=more[more.index('--single')+1]
    query_to_run=f"SELECT omt_all_single_layer(%s,%s,%s,'{layer_name}');"
elif '--layers' in more :
    layer_names=more[more.index('--layers')+1].split(',')
    func_name='||'.join(f"omt_all_single_layer(%s,%s,%s,'{l}')" for l in layer_names)
    query_to_run='SELECT '+func_name+';'


# "ERROR:  too many dynamic shared memory segments" if you have too
#   many running concurrently, it seems 10 is good enough
ts=[Writer(make_new_connection_cursor,query_to_run) for i in range(10)]

start_t=time.time()

tix=0
encountered_zooms=set()
for tile_item in tiles_generator :
    z=tile_item[0]
    encountered_zooms.add(z)
    ts[(tix)%len(ts)].todo.put(tile_item)
    tix+=1

[t.set_zooms(encountered_zooms) for t in ts]
[t.start() for t in ts]
#working...
[t.join() for t in ts]

total_z_bytes={z:sum(t.total_written[z] for t in ts) for z in encountered_zooms}
total_bytes=sum([v for z,v in total_z_bytes.items()])
total_z_count={z:sum(t.total_count[z] for t in ts) for z in encountered_zooms}
print(total_z_count)
print(round(total_bytes*1e-6,2),'MB total written')
for z in encountered_zooms :
    Writer.print_layer_stats(make_new_connection_cursor()[1],ts,z)
print(round(time.time()-start_t,1),'seconds')
