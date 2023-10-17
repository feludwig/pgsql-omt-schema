#!/usr/bin/python3

import jinja2
import psycopg2
import sqlglot
import sqlglot.optimizer
import argparse
import datetime
import typing
import uuid
import re
import os


class GeoTable() :
    def __init__(self,c:psycopg2.extensions.cursor,table_oid:int,
            need_columns:typing.Collection[str],
            aliases:typing.Dict[str,str]) :
        self.aliases=aliases
        self.table_oid=table_oid
        q=c.mogrify('''SELECT attname,atttypid FROM pg_attribute
            WHERE attrelid=%s''',(table_oid,))
        c.execute(q)

        tags_column='tags'
        for (colname,coltype,) in c.fetchall() :
            if colname in need_columns :
                self.__dict__[colname]=f'"{self.aliased(colname)}" AS {colname}'
                self.__dict__[colname+'_v']=f'"{self.aliased(colname)}"'
                self.__dict__[colname+'_ne']=f'("{self.aliased(colname)}" IS NULL)'
        for colname in need_columns :
            if colname not in self.__dict__ :
                self.__dict__[colname]='("'+tags_column+'"'+f"->'{self.aliased(colname)}') AS {colname}"
                self.__dict__[colname+'_v']='("'+tags_column+'"'+f"->'{self.aliased(colname)}')"
                self.__dict__[colname+'_ne']='(NOT ("'+tags_column+'"'+f"?'{self.aliased(colname)}'))"

        c.execute(c.mogrify('''SELECT 
            (SELECT nspname FROM pg_namespace WHERE oid=relnamespace),relname
            FROM pg_class WHERE oid=%s''',(table_oid,)))
        self.table_name='.'.join(c.fetchall()[0])
    def aliased(self,n) :
        if n in self.aliases :
            return self.aliases[n]
        return n

    def __getattr__(self,k) :
        if k not in self.__dict__ :
            raise KeyError(f'Error key "{self.table_name}".{k} not defined')
        return self.__dict__[k]


def make_global_dict(c:psycopg2.extensions.cursor,
        need_columns:typing.Dict[str,typing.Collection[str]],
        aliases:typing.Dict[str,typing.Dict[str,str]])->typing.Dict[str,GeoTable] :
    result={k:[] for k in need_columns.keys()}
    for t in result.keys() :
        c.execute(f'''SELECT oid,relname,relkind,nspname
            FROM (SELECT oid,relkind,relname,
                (SELECT nspname FROM pg_namespace WHERE oid=relnamespace)
                FROM pg_class) AS rels
            WHERE nspname not in ('pg_toast','pg_catalog','information_schema')
            AND relkind NOT IN ('i','c','S') AND relname~E'_{t}$';''')
        for oid,relname,relkind,*_ in c.fetchall() :
            result[t].append(({'r':0,'m':1,'v':2}[relkind],oid))
    for k in result.keys() :
        choice=sorted(result[k])[0]
        result[k]=GeoTable(c,choice[1],need_columns[k],aliases[k])
    return result

# name you want to call it by (so without special symbols) -> name in the database to check
aliases={
    'point':{
        'housenumber':'addr:housenumber',
        'aerodrome_type':'aerodrome:type',
    },
    'line':{
        'mtb_scale':'mtb:scale',
    },
    'polygon':{
        'aerodrome_type':'aerodrome:type',
    },
}

need_columns={
    'point':(
        'housenumber', 'name', 'place', 'aerialway', 'layer',
        'level', 'railway', 'sport', 'office', 'tourism',
        'landuse', 'barrier', 'amenity', 'admin_level',
        'waterway', 'building', 'shop', 'highway',
        'leisure', 'historic', 'indoor', 'aerodrome_type',
        'aeroway', 'iata', 'icao', 'wikipedia', 'wikidata',
        'ele', 'natural', 'ref',

        'way', 'tags', 'osm_id',
    ),
    'line':(
        'amenity', 'bicycle', 'foot', 'horse', 'surface',
        'mtb_scale', 'boundary', 'admin_level', 'highway',
        'railway', 'intermittent', 'bridge', 'tunnel', 'ford',
        'waterway', 'wikipedia', 'wikidata', 'name', 'ele',
        'natural', 'route', 'ref', 'aeroway', 'construction',
        'aerialway', 'shipway', 'man_made', 'public_transport',
        'network', 'oneway', 'ramp', 'service', 'toll',
        'expressway', 'layer', 'level', 'indoor',

        'way', 'tags', 'osm_id',
    ),
    'polygon':(
        'boundary', 'railway', 'sport', 'office', 'tourism',
        'landuse', 'barrier', 'amenity', 'aerialway', 'layer',
        'name', 'indoor', 'waterway', 'building', 'shop',
        'highway', 'leisure', 'historic', 'level', 'place',
        'admin_level', 'bridge', 'tunnel', 'ford',
        'water', 'intermittent', 'natural', 'covered',
        'ref','aeroway', 'aerodrome_type', 'iata', 'icao',
        'ele', 'wetland',

        'way_area', 'way', 'tags', 'osm_id',
    ),
}

#type var
s_where_t=sqlglot.expressions.Where

def remove_way_var(s_where:s_where_t)->typing.Optional[s_where_t] :
    #   * remove ... AND ST_intersects(way...)
    #       -> and replace with AND TRUE -> and simplify away
    s_intersects=[i for i in s_where.find_all(sqlglot.expressions.Anonymous) if i.name.lower()=='st_intersects']
    if len(s_intersects)==0 :
        #print('NO way to index over FOUND'), not very important: probably part of a subquery
        return sqlglot.optimizer.simplify.simplify(s_where)
    s_intersects[0].replace(sqlglot.expressions.TRUE)
    return sqlglot.optimizer.simplify.simplify(s_where)

def remove_z_var(s_where:s_where_t)->typing.Collection[typing.Dict[str,s_where_t]] :
    ''' Will return a list of the multiplied WHERE along possible z-conditions
    '''
    #   * still need to remove z dependency:
    # [...] OR ("way_area" > 1500 AND z >= 14) OR ("way_area" > 8000 AND z >= 11)
    # -> (1) [...] OR ("way_area" > 1500 AND [TRUE]) OR <--REMOVE:("way_area" > 8000 AND z >= 11)-->
    # -> (2) [...] OR <--REMOVE:("way_area" > 1500 AND z>=14)--> OR ("way_area" > 8000 AND [TRUE])
    # as in: for every AND that contains any z references :
    # replace the z reference with a TRUE and remove all other z-referencing ANDs,
    # then sqlglot.simplify() that and make multiple indexes.

    # add comments to sql that e.g way_area should have BETWEEN constraints explicitly
    # where z-implied

    result=[]

    s_where_with_uuids=s_where.copy()
    # sqlglot will say Identifier('z') == Identifier('z') but we don't want that!
    # make these unique wrt eachother
    for id_obj in s_where_with_uuids.find_all(sqlglot.expressions.Identifier) :
        if id_obj.name=='z' :
            id_obj.replace(sqlglot.parse_one('z_'+str(uuid.uuid1()).replace('-','_')))
    all_zs=[ident for ident in s_where_with_uuids.find_all(sqlglot.expressions.Identifier) if ident.name[:2]=='z_']

    for id_z in all_zs :
        one_result={}
        def trsf(n) :
            if n.key in ('gt','lt','gte','lte','eq') :
                sub_ids=[i for i in n.left.find_all(sqlglot.expressions.Identifier)]
                sub_ids.extend([i for i in n.right.find_all(sqlglot.expressions.Identifier)])
                if id_z in sub_ids :
                    p_repr=n.sql().split(' ')
                    if p_repr[0][:2]=='z_' :
                        p_repr[0]='z'
                        p_repr[1]={'=':'eq','<':'lt','<=':'lte','>':'gt','>=':'gte'}[p_repr[1]]
                    elif p_repr[2][:2]=='z_' :
                        p_repr[2]='z'
                        p_repr[1]={'=':'eq','>':'lt','>=':'lte','<':'gt','<=':'gte'}[p_repr[1]]
                    one_result['parent']='_'.join(p_repr)
                    return sqlglot.expressions.TRUE
                for other_id_z in all_zs :
                    if id_z!=other_id_z and other_id_z in sub_ids :
                        return sqlglot.expressions.FALSE
            return n
        one_result['s']=s_where_with_uuids.transform(trsf,copy=True)
        one_result['s']=sqlglot.optimizer.simplify.simplify(one_result['s'])
        result.append(one_result)
    return result

def parse_indexed_create(sql_script:str)->typing.Iterator[typing.Dict[str,typing.Any]] :
    uncommented=[i if i.find('--')<0 else i[:i.index('--')] for i in sql_script.split('\n')]
    collapsed_newlines=' '.join(uncommented)
    regex_get_funcs=r'FUNCTION\s+(?P<funcname>[^\(]+)(?P<functypedef>[^\$]+)\s+AS\s+\$\$(?P<funcbody>[^\$]+)\$\$[^\$]*LANGUAGE\s+(?P<funclang>[^\s]+)\s'
    for match in re.finditer(regex_get_funcs,collapsed_newlines) :
        if match.group('funclang') not in ("'sql'",'"sql"') :
            continue
        func_name=match.group('funcname')
        func_body_str=match.group('funcbody')
        if ( func_body_str.lower().find('st_asmvt(')>=0 or func_name=='omt_all'
                or func_body_str.find('&&')>=0 or func_name.find('_get_')>=0 ) :
            # '&&' operator unsupported in sqlglot
            # _get_ remove: filter out utils functions
            continue

        s_func_body=sqlglot.parse_one(func_body_str,dialect='postgres')
        #print('BLOCK START')
        #print(s_func_body)
        #print('BLOCK END')
        for s_from in s_func_body.find_all(sqlglot.expressions.From) :
            t_name=s_from.name #table name
            t_s=t_name.split('_')[-1]
            if t_name.find('planet_osm')>=0 :
                # extract the WHERE corresponding to this s_from
                # to create corresponding index on
                # planet_osm_* USING GIST(way)
                s_where=s_from.parent_select.find(sqlglot.expressions.Where)
                if s_where==None :
                    # just proactively take the parent.parent where
                    s_where=s_from.parent_select.parent_select.find(sqlglot.expressions.Where)
                    if s_where==None :
                        print('ABANDONING: too complicated subquery, next function')
                        continue

                # s_where references some data that should not be indexed:
                s_where=remove_way_var(s_where.copy())
                s_wheres=remove_z_var(s_where)
                def assemble_dict(where_sql:str,z:bool,parent:str) :
                    r={'func':func_name,'table':t_name,
                        'where':where_sql,
                        'geom':'way'}
                    r['name']='idx_'+r['func'].split('.')[-1]+'_'+t_s
                    if z :
                        r['name']=r['name']+'_'+parent
                    return r

                if len(s_wheres)!=0 :
                    for o_r in s_wheres :
                        rslt=o_r['s'].sql(dialect='postgres')
                        if rslt=='WHERE FALSE' :
                            #simplified to the point of nothing left
                            continue
                        yield assemble_dict(rslt,True,o_r['parent'])
                else :
                    yield assemble_dict(s_where.sql(dialect='postgres'),False,None)

def sql_index_command(data:typing.Dict[str,str],operation:str)->str :
    if operation=='create' :
        return f"CREATE INDEX CONCURRENTLY IF NOT EXISTS {data['name']} ON {data['table']} USING GIST({data['geom']}) {data['where']}"
    elif operation=='drop' :
        return f"DROP INDEX IF EXISTS {data['name']}"

def run_sql_indexes(c:psycopg2.extensions.cursor,sql_script:str,command:str) :
    ''' Parse out indexes that could be useful from the compiled template sql_script.
    command: create -> CREATE INDEX IF NOT EXISTS
    command: drop -> DROP INDEX
    command: names -> return the index names as a list, do nothing else
    '''
    names=[]
    notices=[]
    start=datetime.datetime.now()
    #collapse generator to get out error messages and flush the
    # annoying "applying array index offset" at the start
    payload=list(parse_indexed_create(sql_script))
    #also for len(payload) progress reports
    for ix,d in enumerate(payload) :
        start_one=datetime.datetime.now()
        if command=='names' :
            names.append(d['name'])
            continue
        print(ix+1,'/',len(payload),'\t',len(d['where']),d['name'])
        try :
            c.execute(sql_index_command(d,command))
        except psycopg2.Error as err :
            print(sql_index_command(d,command))
            raise err
        for i in access.notices :
            if i not in notices :
                print(i)
                notices.append(i)
        print(command,d['name'],'in',(datetime.datetime.now()-start_one))
    if command=='names' :
        return names
    print(command,'all in',(datetime.datetime.now()-start))
    print(datetime.datetime.now(),'finished')


if __name__=='__main__' :
    import sys
    access=psycopg2.connect(sys.argv[1])
    c=access.cursor()
    e=jinja2.Environment(
        loader=jinja2.FileSystemLoader(os.path.dirname(__file__)),
    )
    e.globals=make_global_dict(c,need_columns,aliases)
    t=e.get_template('omt-functions.sql')
    sql_script=t.render(**{
        # include osm_ids in some layers: useful for
        # map.on('click') looking up specific features
        'with_osm_id':True,
        # transportation aggregates roads, remove osm_id if they are
        # "uninteresting", heuristic: for now just when name IS NULL.
        # only has an effect if with_osm_id=True
        'transportation_aggregate_osm_id_reduce':True,
        # WARNING: set to '' to ignore. else NEEDS to have a trailing comma
        # this is only added at the end, after the typedefed-rows have been
        #   generated. tags are not available anymore
        'additional_name_columns':'name AS "name:latin",',
        # other non-spec behaviour: the rank value is still filtering out items
        # on z>17 even though the spec says it SHOULD show all.
        # to force show all at z>=17, this workaround:
        'same_rank_poi_high_zooms':True,
        # NO SPACES in value!
        'omt_typ_pref':'row_omt',
        # all functions except omt_all_func will have this prefix
        'omt_func_pref':'public.omt',
        # DOES NOT use the omt_func_pref
        'omt_all_func':'public.omt_all',
    })
    if len(sys.argv)>2 and sys.argv[2]=='--print' :
        print(sql_script)
    elif len(sys.argv)>2 and sys.argv[2]=='--index' :
        access.commit()
        # WARN: enable transaction-less CREATE INDEX;
        access.autocommit=True
        run_sql_indexes(c,sql_script,'create')
    elif len(sys.argv)>2 and sys.argv[2]=='--index-drop' :
        access.commit()
        # WARN: enable transaction-less CREATE INDEX;
        access.autocommit=True
        run_sql_indexes(c,sql_script,'drop')
    elif len(sys.argv)>2 and sys.argv[2]=='--index-print' :
        for d in parse_indexed_create(sql_script) :
            print(sql_index_command(d,'create'))
    elif len(sys.argv)>2 and sys.argv[2]=='--index-names' :
        for n in run_sql_indexes(c,sql_script,'names') :
            print(n)
    else :
        try :
            c.execute(sql_script)
        except psycopg2.errors.SyntaxError as err :
            if str(err).find('"AS"')>=0 :
                print(end='\033[31m')
                print('WARNING: Use a "_v" at end of template column name for omitting the "AS": eg {{polygon.boundary_v}} ')
                print('REMINDER: "_v" for the value of the column')
                print(end='\033[0m')
            raise err
        print(*access.notices)
        cols=[col.name for col in c.description]
        while (row:=c.fetchone())!=None :
            print({k:v for k,v in zip(cols,row)})
        c.execute('COMMIT;')
