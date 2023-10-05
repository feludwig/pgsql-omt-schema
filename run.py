#!/usr/bin/python3

import jinja2
import psycopg2
import argparse
import typing
import dataclasses
import os

@dataclasses.dataclass
class Column :
    name:str
    type:str

class TypeHandler() :
    def __init__(self,c:psycopg2.extensions.cursor) :
        c.execute('SELECT oid,typname,typcategory FROM pg_type;')
        self.types={}
        for (oid,typname,typcategory) in c.fetchall() :
            self.types[oid]=(typname,typcategory)
    def is_similar_type(self,a,b) :
        try :
            if isinstance(a,int) :
                a_typ=self.types[a]
            else :
                a_typ=[i for i in self.types.values() if i[0]==a][0]
            if isinstance(b,int) :
                b_typ=self.types[b]
            else :
                b_typ=[i for i in self.types.values() if i[0]==b][0]
            if a_typ[0]==b_typ[0] :
                return True
            if a_typ[1]==b_typ[1] :
                return True
        except IndexError :
            print(a,b,'types uncomparable')
            exit(1)
        return False


class GeoTable() :
    def __init__(self,c:psycopg2.extensions.cursor,th:TypeHandler,table_oid:int,
            need_columns:typing.Collection[Column],
            aliases:typing.Dict[str,str]) :
        self.aliases=aliases
        self.table_oid=table_oid
        q=c.mogrify('''SELECT attname,atttypid FROM pg_attribute
            WHERE attrelid=%s''',(table_oid,))
        c.execute(q)
        need_columns_byname={col.name:col for col in need_columns}
        tags_column=[col.name for col in need_columns if col.type=='hstore'][0]

        for (colname,coltype,) in c.fetchall() :
            if colname in need_columns_byname :
                col=need_columns_byname[colname]
                if th.is_similar_type(coltype,col.type) :
                    self.__dict__[col.name]=f'"{self.aliased(col.name)}"'
                else :
                    self.__dict__[col.name]=f'("{self.aliased(col.name)}"::{col.type})'
                    self.__dict__[col.name+'_a']=self.__dict__[col.name]+f' AS "{col.name}"'
        for col in need_columns :
            if col.name not in self.__dict__ :
                if th.is_similar_type('text',col.type) :
                    self.__dict__[col.name]='("'+tags_column+'"'+f"->'{col.name}')"
                    self.__dict__[col.name+'_a']=self.__dict__[col.name]+f' AS "{col.name}"'
                else :
                    self.__dict__[col.name]='(("'+tags_column+'"'
                    self.__dict__[col.name]+=f"->'{col.name}')::{col.type})"
                    self.__dict__[col.name+'_a']=self.__dict__[col.name]+f' AS "{col.name}"'

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
            raise KeyError(f'Error key {k} not defined')
        return self.__dict__[k]


def make_global_dict(c:psycopg2.extensions.cursor,
        need_columns:typing.Dict[str,typing.Collection[Column]],
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
    th=TypeHandler(c)
    for k in result.keys() :
        choice=sorted(result[k])[0]
        result[k]=GeoTable(c,th,choice[1],need_columns[k],aliases[k])
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
        Column('housenumber','text'),
        Column('name','text'),
        Column('place','text'),
        Column('aerialway','text'),
        Column('layer','text'),
        Column('level','text'),
        Column('railway','text'),
        Column('sport','text'),
        Column('office','text'),
        Column('tourism','text'),
        Column('landuse','text'),
        Column('barrier','text'),
        Column('amenity','text'),
        Column('admin_level','text'),

        Column('way','geometry'),
        Column('tags','hstore'),
        Column('z_order','int4'),
        Column('osm_id','int8'),
    ),
    'line':(
        Column('amenity','text'),
        Column('bicycle','text'),
        Column('foot','text'),
        Column('horse','text'),
        Column('surface','text'),
        Column('mtb_scale','text'),
        Column('boundary','text'),
        Column('admin_level','text'),
        Column('highway','text'),
        Column('railway','text'),
        Column('intermittent','text'),

        Column('way','geometry'),
        Column('tags','hstore'),
    ),
    'polygon':(
        Column('boundary','text'),

        Column('tags','hstore'),
        Column('osm_id','int8'),
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
