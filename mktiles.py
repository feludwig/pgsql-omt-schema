#!/usr/bin/python3

import sys
import psycopg2
import os
import time
import threading
import queue
import typing
printer_lock=threading.Lock()

import run #local

format='pbf'


#maximally parallelize database:new connections only
def make_new_connection_cursor() :
    access=psycopg2.connect(dbaccess)
    return access.cursor()

def gen_zxy_readinput()->typing.Iterator[[int,int,int]] :
    while True :
        try :
            line=input()
        except EOFError :
            #finished
            return
        z,x,y=line.split(' ')
        yield (int(z),int(x),int(y))

def gen_zxy_range(z:str,x:str,y:str)->typing.Iterator[[int,int,int]] :
    if z.find('-')>=0 :
        # z range, x and y are specified for starting zoom!
        zs=list(range(*map(int,z.split('-'))))
        #inclusive range
        zs.append(zs[-1]+1)
    else :
        zs=[int(z)]
    if x.find('-')>=0 :
        xs=list(range(*map(int,x.split('-'))))
        #inclusive range
        xs.append(xs[-1]+1)
    elif x=='*' :
        xs=list(range(2**zs[0]))
    else :
        xs=[int(x)]
    if y.find('-')>=0 :
        ys=list(range(*map(int,y.split('-'))))
        #inclusive range
        ys.append(ys[-1]+1)
    elif y=='*' :
        ys=list(range(2**zs[0]))
    else :
        ys=[int(y)]
    for z in zs :
        scale=2**(z-zs[0])
        for xr in xs :
            for x in range(xr*scale,(xr+1)*scale) :
                for yr in ys :
                    for y in range(yr*scale,(yr+1)*scale) :
                        yield (z,x,y)


class Writer(threading.Thread) :
    def __init__(self,c) :
        threading.Thread.__init__(self)
        self.c=c
        self.finished=False
        self.todo=queue.Queue(100)
    def set_zooms(self,zs) :
        self.total_written={z:0 for z in zs}
        self.total_count={z:0 for z in zs}
        self.per_layer_stats={z:{} for z in zs}
    def add_layer_stats_line(self,z,line:dict) :
        ln=line['name']
        if ln not in self.per_layer_stats[z] :
            self.per_layer_stats[z][ln]=[0]*4
        self.per_layer_stats[z][ln][0]+=1
        self.per_layer_stats[z][ln][1]+=line['pcent']
        self.per_layer_stats[z][ln][2]+=line['bytes']
        self.per_layer_stats[z][ln][3]+=line['rowcount']

    @classmethod
    def print_layer_stats(cls,c:psycopg2.extensions.cursor,list_of_self,z) :
        """ Use database for pg_size_pretty...
        """
        def get_size_pretty(d:float) :
            c.execute(c.mogrify('SELECT pg_size_pretty(%s::numeric);',(d,)))
            return c.fetchone()[0]
        per_layer_stats={}
        #collect all data
        for i in list_of_self :
            for k,v in i.per_layer_stats[z].items() :
                if k not in per_layer_stats :
                    per_layer_stats[k]=[0]*4
                for ix in (0,1,2,3) :
                    per_layer_stats[k][ix]+=v[ix]
        #print
        headers=['layer_name','avg_pcent','avg_bytes','avg_rowcount']
        data=[(k,
            str(round(v[1]/v[0],1)),
            get_size_pretty(round(v[2]/v[0],1)),str(round(v[3]/v[0])),
            ) for k,v in per_layer_stats.items()]
        run.print_table(data,headers)


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

    def process(self,z,x,y) :
        success=False
        for i in range(5) : #try again 5 times
            try :
                self.c.execute(
                    self.c.mogrify('SELECT * FROM omt_all_with_stats(%s,%s,%s);',(z,x,y)))
                success=True
                break
            # when function was redefined while running/did not exist when needed
            except psycopg2.Error as err :
                self.c.execute('ABORT;')
                with printer_lock :
                    print(f'{z:2}/{x}/{y}.{format}\t','failed SQL retrying')
        if not success :
            with printer_lock :
                print(f'{z:2}/{x}/{y}.{format}\t','retried 5 times, abandoning')
            return
        result=[dict(zip([col.name for col in self.c.description],i)) for i in self.c.fetchall()]
        for line in result :
            if line['name']=='ALL' :
                out_data=line['data']
            else :
                self.add_layer_stats_line(z,line)
        if not os.path.exists(f'{outdir}/{z}/{x}') :
            os.makedirs(f'{outdir}/{z}/{x}',exist_ok=True)
        with open(f'{outdir}/{z}/{x}/{y}.{format}','wb') as f:
            bs_written=f.write(out_data)
        self.total_written[z]+=bs_written
        self.total_count[z]+=1
        with printer_lock :
            print(f'{z:2}/{x}/{y}.{format}\t',bs_written,'bytes')


dbaccess,mode,outdir,*more=sys.argv[1:]
if mode=='--range' :
    z,x,y=more
    tiles_generator=gen_zxy_range(z,x,y)
elif mode=='--list' :
    tiles_generator=gen_zxy_readinput()
else :
    print('unrecognized mode')
    exit(1)



ts=[Writer(make_new_connection_cursor()) for i in range(5)]

start=time.time()

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
total_count=sum(total_z_count.values())
print(round(total_bytes*1e-6,2),'MB total written')
for z in encountered_zooms :
    print(f'z{z:02}:')
    Writer.print_layer_stats(make_new_connection_cursor(),ts,z)
    if total_z_count[z]==0 :
        per_tile_kb_size=0
    else :
        per_tile_kb_size=round(total_z_bytes[z]/total_z_count[z]*1e-3,2)
    print('total',round(total_z_bytes[z]*1e-6,2),'MB, average',
            per_tile_kb_size,'KB/tile,',total_z_count[z],'tiles')
print(round(time.time()-start,1),'seconds')
