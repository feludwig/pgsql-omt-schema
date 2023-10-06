#!/usr/bin/python3

import jinja2
import psycopg2
import argparse
import typing
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
                self.__dict__[colname]=f'"{self.aliased(colname)}"'
                self.__dict__[colname+'_v']=f'"{self.aliased(colname)}"'
        for colname in need_columns :
            if colname not in self.__dict__ :
                self.__dict__[colname]='("'+tags_column+'"'+f"->'{colname}') AS {colname}"
                self.__dict__[colname+'_v']='("'+tags_column+'"'+f"->'{colname}')"

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
            raise KeyError(f'Error key {self.table_name}.{k} not defined')
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
    },
    'line':{
        'mtb_scale':'mtb:scale',
    },
    'polygon':{
    },
}

need_columns={
    'point':(
        'housenumber', 'name', 'place', 'aerialway', 'layer',
        'level', 'railway', 'sport', 'office', 'tourism',
        'landuse', 'barrier', 'amenity', 'admin_level',
        'waterway', 'building', 'shop', 'highway',
        'leisure', 'historic', 'indoor', 

        'way', 'tags', 'osm_id',
    ),
    'line':(
        'amenity', 'bicycle', 'foot', 'horse', 'surface',
        'mtb_scale', 'boundary', 'admin_level', 'highway',
        'railway', 'intermittent',

        'way', 'tags', 'osm_id',
    ),
    'polygon':(
        'boundary', 'railway', 'sport', 'office', 'tourism',
        'landuse', 'barrier', 'amenity', 'aerialway', 'layer',
        'name', 'indoor', 'waterway', 'building', 'shop',
        'highway', 'leisure', 'historic', 'level', 'place',

        'way_area', 'way', 'tags', 'osm_id',
    ),
}


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
        'with_osm_id':True,
        # WARNING: set to '' to ignore. else NEEDS to have a trailing comma
        # this is only added at the end, after the typedefed-rows have been
        #   generated. tags are not available anymore
        'additional_name_columns':'name AS "name:latin",',
        # NO SPACES!
        'omt_typ_pref':'row_omt',
        # all functions except omt_all_func will have this prefix
        'omt_func_pref':'public.omt',
        # DOES NOT use the omt_func_pref
        'omt_all_func':'public.omt_all',
        'debug':True,
    })
    if len(sys.argv)>2 and sys.argv[2]=='--print' :
        print(sql_script)
    else :
        c.execute(sql_script)
        print(*access.notices)
        cols=[col.name for col in c.description]
        while (row:=c.fetchone())!=None :
            print({k:v for k,v in zip(cols,row)})
        c.execute('COMMIT;')
