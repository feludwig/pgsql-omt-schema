#!/usr/bin/python3

import jinja2
import psycopg2
import sqlglot
import sqlglot.optimizer
import argparse
import typing
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
        'railway', 'intermittent', 'bridge', 'tunnel', 'ford',
        'waterway',

        'way', 'tags', 'osm_id',
    ),
    'polygon':(
        'boundary', 'railway', 'sport', 'office', 'tourism',
        'landuse', 'barrier', 'amenity', 'aerialway', 'layer',
        'name', 'indoor', 'waterway', 'building', 'shop',
        'highway', 'leisure', 'historic', 'level', 'place',
        'admin_level', 'bridge', 'tunnel', 'ford',
        'water', 'intermittent', 'natural', 'covered',
        'ref','aeroway',

        'way_area', 'way', 'tags', 'osm_id',
    ),
}

def parse_indexed_create(sql_script:str) :
    uncommented=[i if i.find('--')<0 else i[:i.index('--')] for i in sql_script.split('\n')]
    collapsed_newlines=' '.join(uncommented)
    for match in re.finditer(r'FUNCTION\s+(?P<funcname>[^\(]+)(?P<functypedef>[^\$]+)\s+AS\s+\$\$(?P<funcbody>[^\$]+)\$\$[^\$]*LANGUAGE\s+(?P<funclang>[^\s]+)\s',collapsed_newlines) :
        if match.group('funclang') not in ("'sql'",'"sql"') :
            continue
        func_name=match.group('funcname')
        func_body_str=match.group('funcbody')
        if func_body_str.lower().find('st_asmvt(')>=0 or func_name=='omt_all':
            continue
        print('NAME',func_name)
        s_func_body=sqlglot.parse_one(func_body_str.replace('&&','=='),dialect='postgres')
        #print('BLOCK START')
        #print(s_func_body)
        #print('BLOCK END')
        for s_from in s_func_body.find_all(sqlglot.expressions.From) :
            print('OUTPUTNAME',s_from.name)
            if s_from.name.find('planet_osm')>=0 :
                # extract the WHERE corresponding to this s_from
                # and create corresponding index on
                # planet_osm_* USING GIST(way)
                s_where=s_from.parent_select.find(sqlglot.expressions.Where)
                if s_where==None :
                    print('WARN: UNION ALL SITUATION, NEED INDEXES MULTIPLE ON:')
                    # TODO: still need to deal with this case
                    # TODO: if s_from.parent_select.parent_select, just proactively check it and merge the 
                    #   two wheres with an AND
                    print([s_f.name for s_f in s_from.parent_select.parent_select.find_all(sqlglot.expressions.From)])
                    s_where=s_from.parent_select.parent_select.find(sqlglot.expressions.Where)
                #print('SFROM',s_from,'SWHERE',s_where)
                s_intersects=[i for i in s_where.find_all(sqlglot.expressions.Anonymous) if i.name.lower()=='st_intersects']
                if len(s_intersects)==0 :
                    print('NO way to index over FOUND')
                    continue
                s_intersects[0].replace(sqlglot.expressions.TRUE)
                s_where=sqlglot.optimizer.simplify.simplify(s_where)
                # still need to remove z dependency:
                # [...] AND ("way_area" > 1500 OR z >= 14) AND ("way_area" > 8000 OR z >= 11)
                # -> (1) [...] AND ("way_area" > 1500 OR [TRUE]) <--REMOVE:AND ("way_area" > 8000 OR z >= 11)-->
                # -> (2) [...] AND <--REMOVE:("way_area" > 1500 OR z>=14) AND ("way_area" > 8000 OR [TRUE])
                # as in: for every AND that contains any z references :
                # replace the z reference with a TRUE and remove all other z-referencing ANDs,
                # then sqlglot.simplify() that and make multiple indexes.
                # add comments to sql that e.g way_area should have BETWEEN constraints explicitly
                # where z-implied
                print('SWHERE',s_where)
            print()
        print()

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
        'debug':True,
    })
    if len(sys.argv)>2 and sys.argv[2]=='--print' :
        print(sql_script)
    elif len(sys.argv)>2 and sys.argv[2]=='--index' :
        parse_indexed_create(sql_script)
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
