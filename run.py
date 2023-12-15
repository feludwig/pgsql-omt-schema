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

import math
import jinja2
import psycopg2
import sqlglot
import sqlglot.optimizer
import argparse
import datetime
import typing
import uuid
import sys
import re
import os

# name you want to call column by (so without special symbols) -> name in the database to check
aliases={
    'point':{
        'housenumber':'addr:housenumber',
        'aerodrome_type':'aerodrome:type',
        'tower_type':'tower:type',
        'admin_centre_4':'admin_centre:4',
        'iso3166_1_alpha2':'ISO3166-1:alpha2',
        'iso3166_1':'ISO3166-1',
        'mtb_scale':'mtb:scale',
        'name_en':'name:en',
        'demolished_building':'demolished:building',
    },
    'line':{
        'housenumber':'addr:housenumber',
        'mtb_scale':'mtb:scale',
        'iso3166_1_alpha2':'ISO3166-1:alpha2',
        'iso3166_1':'ISO3166-1',
        'demolished_building':'demolished:building',
    },
    'polygon':{
        'housenumber':'addr:housenumber',
        'aerodrome_type':'aerodrome:type',
        'building_levels':'building:levels',
        'building_part':'building:part',
        'tower_type':'tower:type',
        'admin_centre_4':'admin_centre:4',
        'iso3166_1_alpha2':'ISO3166-1:alpha2',
        'iso3166_1':'ISO3166-1',
        'mtb_scale':'mtb:scale',
        'demolished_building':'demolished:building',
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
        'ele', 'natural', 'ref', 'man_made', 'tower_type',
        'start_date', 'admin_centre_4', 'population',
        'iso3166_1_alpha2','iso3166_1','country_code_fips',
        'capital', 'information','network','surface','foot',
        'horse','bicycle','toll','oneway','ramp','bridge',
        'tunnel','ford','service','expressway','mtb_scale',
        'country_code_iso3166_1_alpha_2','name_en',
        'demolished_building',

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
        'expressway', 'layer', 'level', 'indoor','country_code_fips',
        'iso3166_1_alpha2','iso3166_1', 'housenumber', 'disputed',
        'disputed_name','country_code_iso3166_1_alpha_2',
        'demolished_building',

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
        'ele', 'wetland', 'housenumber', 'building_levels',
        'building_part', 'min_height', 'height', 'location',
        'man_made', 'tower_type', 'start_date', 'wikidata',
        'wikipedia', 'admin_centre_4', 'population',
        'iso3166_1_alpha2','iso3166_1','country_code_fips',
        'capital', 'information','protection_title',
        'construction','public_transport','network',
        'oneway','ramp','service','toll','expressway',
        'bicycle','foot','horse','mtb_scale','surface',
        'country_code_iso3166_1_alpha_2',
        'demolished_building',

        'way_area', 'way', 'tags', 'osm_id',
    ),
}

"""
TODO:
    get_center_tile move to {{polygon.table_name}}
    organize sqlglot index stuff into separate class
"""

class GeoTable() :
    def __init__(self,c:psycopg2.extensions.cursor,table_oid:int,
            need_columns:typing.Collection[str],
            aliases:typing.Dict[str,str]) :
        self.aliases=aliases
        self.reverse_aliases={v:k for k,v in aliases.items()}
        aliased_need_columns=[]
        for i in need_columns :
            if i in self.aliases :
                aliased_need_columns.append(self.aliases[i])
        self.table_oid=table_oid
        c.execute(c.mogrify('''SELECT
            (SELECT nspname FROM pg_namespace WHERE oid=relnamespace),relname
            FROM pg_class WHERE oid=%s''',(table_oid,)))
        self.table_schema,self.table_name=c.fetchall()[0]
        self.full_table_name=self.table_schema+'.'+self.table_name
        q=c.mogrify('''SELECT attname,atttypid FROM pg_attribute
            WHERE attrelid=%s''',(table_oid,))
        c.execute(q)
        tags_column=f'{self.table_name}."tags"'
        self.actual_columns=[]

        # see omt-functions.sql for the meaning of these
        for (colname,coltype,) in c.fetchall() :
            self.actual_columns.append(colname)
            if colname in need_columns or colname in aliased_need_columns:
                k=self.refer(colname)
                self.__dict__[k]=f'{self.table_name}."{self.aliased(colname)}" AS {self.refer(colname)}'
                tg=tags_column+f"->'{self.aliased(colname)}'"
                self.__dict__[k+'_ct']=f'COALESCE({self.table_name}."{self.aliased(colname)}",{tg}) AS {self.refer(colname)}'
                self.__dict__[k+'_ctv']=f'COALESCE({self.table_name}."{self.aliased(colname)}",{tg})'
                self.__dict__[k+'_v']=f'{self.table_name}."{self.aliased(colname)}"'
                self.__dict__[k+'_ne']=f'({self.table_name}."{self.aliased(colname)}" IS NULL)'
                self.__dict__[k+'_e']=f'({self.table_name}."{self.aliased(colname)}" IS NOT NULL)'

        for colname in need_columns :
            if colname not in self.__dict__ :
                k=self.refer(colname)
                self.__dict__[k]='('+tags_column+f"->'{self.aliased(colname)}') AS {self.refer(colname)}"
                self.__dict__[k+'_ct']=self.__dict__[k]
                self.__dict__[k+'_v']='('+tags_column+f"->'{self.aliased(colname)}')"
                self.__dict__[k+'_ctv']=self.__dict__[k+'_v']
                self.__dict__[k+'_e']='('+tags_column+f"?'{self.aliased(colname)}')"
                self.__dict__[k+'_ne']=f"(NOT {self.__dict__[k+'_e']})"

    def aliased(self,n) :
        if n in self.aliases :
            return self.aliases[n]
        return n

    def refer(self,n) :
        ''' Reverse-resolve from n the aliased name, get the reference name
        '''
        if n in self.reverse_aliases :
            return self.reverse_aliases[n]
        return n

    def __getattr__(self,k) :
        if k not in self.__dict__ :
            raise KeyError(f'Error key "{self.table_name}".{k} not defined')
        return self.__dict__[k]

# from https://wiki.openstreetmap.org/wiki/Slippy_map_tilenames#Python
def deg2num(lat_deg, lon_deg, zoom):
    lat_rad = math.radians(lat_deg)
    n = 1 << zoom
    xtile = int((lon_deg + 180.0) / 360.0 * n)
    ytile = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
    return xtile, ytile

def get_center_tile(c:psycopg2.extensions.cursor,osm_polygon_id:int,zoom=15)->(int,int,int) :
    """ Returns z,x,y coordinates of tile over the centroid of the osm_polygon
    """
    q=c.mogrify('''SELECT ST_Y(a.a) AS lat,ST_X(a.a) AS lon
        FROM (SELECT ST_Transform(st_centroid(way),4326)
            FROM planet_osm_polygon WHERE osm_id=%s limit 1
        )AS a(a);''',(osm_polygon_id,))
    c.execute(q)
    try :
        lat,lon=c.fetchone()
    except TypeError :
        print('WARNING: polygon with id',osm_polygon_id,'not found in database',file=sys.stderr)
        print('Using test tile',(zoom,0,0),file=sys.stderr)
        return (zoom,0,0)
    return (zoom,*deg2num(lat,lon,zoom))

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

#type var
s_where_t=sqlglot.expressions.Where

def resolve_aliases(s_where:s_where_t,gt:GeoTable)->s_where_t :
    # check all identifiers, if any column matches then replace it with
    # the geotable's column name
    local_alias=gt.aliases
    for i in s_where.find_all(sqlglot.expressions.Identifier) :
        if i.name not in gt.actual_columns and i.name in gt.__dict__ :
            # replace "office" by "tags"->'office'
            i.replace(sqlglot.parse_one(gt.__dict__[i.name+'_v'],dialect='postgres'))
        if i.name in local_alias :
            i.replace(sqlglot.parse_one('"'+local_alias[i.name]+'"'))
    return s_where

def remove_way_var(s_where:s_where_t)->s_where_t :
    #   * remove ... AND ST_intersects(way...)
    #       -> and replace with AND TRUE -> and simplify away
    s_intersects=[i for i in s_where.find_all(sqlglot.expressions.Anonymous) if i.name.lower()=='st_intersects']
    if len(s_intersects)!=0 :
        s_intersects[0].replace(sqlglot.expressions.TRUE)
    try :
        return sqlglot.optimizer.simplify.simplify(s_where)
    except ValueError :
        return s_where

def remove_way_area(s_where:s_where_t)->typing.Tuple[bool,s_where_t] :
    rslt={'found':False} #accessible memory from inside function
    def trsf(n) :
        if n.key in ('gt','lt','gte','lte','eq') :
            sub_id_names=[i.name for i in n.left.find_all(sqlglot.expressions.Identifier)]
            sub_id_names.extend([i.name for i in n.right.find_all(sqlglot.expressions.Identifier)])
            if 'way_area' in sub_id_names :
                rslt['found']=True
                return sqlglot.expressions.TRUE
        return n
    # can't do a oneliner because rslt['found'] needs to get written into before returning
    r=s_where.transform(trsf,copy=True)
    return rslt['found'],r


def remove_z_var(s_where:s_where_t)->typing.Collection[typing.Dict[str,s_where_t]] :
    """ Will return a list of the multiplied WHERE along possible z-conditions
    """
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
        try :
            one_result['s']=sqlglot.optimizer.simplify.simplify(one_result['s'])
        except ValueError :
            pass
        result.append(one_result)
    return result

def parse_indexed_create_unique(sql_script:str,tmpl_defined:dict)->typing.Iterator[typing.Dict[str,typing.Any]] :
    result={}
    additional_keys=('geom','has_way_area')
    for i in list(parse_indexed_create(sql_script,tmpl_defined)) :
        k=(i['table'],i['where'])
        if k not in result :
            result[k]=[]
        result[k].append((i['name'],[i[k] for k in additional_keys]))
    for k,v in result.items() :
        choice=sorted(v)[0]
        yield {'table':k[0],'where':k[1],'name':choice[0],**{k:v for k,v in zip(additional_keys,choice[1])}}


def parse_indexed_create(sql_script:str,tmpl_defined:dict)->typing.Iterator[typing.Dict[str,typing.Any]] :
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

        for s_from in s_func_body.find_all(sqlglot.expressions.From) :
            t_name=s_from.name #table name
            # do NOT get confused by aa_line CTE, look up exact {}.table_name
            if t_name in [tmpl_defined[k].table_name for k in ('point','line','polygon','roads') if k in tmpl_defined]:
                t_s=t_name.split('_')[-1]
                gt=tmpl_defined[t_s]
                # extract the WHERE corresponding to this s_from
                # to create corresponding index on
                # planet_osm_* USING GIST(way)
                s_where=s_from.parent_select.find(sqlglot.expressions.Where)
                if s_where==None :
                    if s_from.parent_select.parent_select==None :
                        continue
                    # just proactively take the parent.parent where
                    s_where=s_from.parent_select.parent_select.find(sqlglot.expressions.Where)
                    if s_where==None :
                        continue

                # s_where references some data that should not be indexed:
                s_where=remove_way_var(s_where.copy())
                s_where=resolve_aliases(s_where,gt)
                has_way_area,s_where=remove_way_area(s_where)
                s_wheres=remove_z_var(s_where)
                def assemble_dict(where_sql:str,z:bool,parent:str,has_way_area:bool) :
                    r={'func':func_name,'table':t_name,
                        'where':where_sql,
                        'has_way_area':has_way_area,
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
                        yield assemble_dict(rslt,True,o_r['parent'],has_way_area)
                else :
                    yield assemble_dict(s_where.sql(dialect='postgres'),False,None,has_way_area)

def sql_index_command(data:typing.Dict[str,str],operation:str)->str :
    if operation=='create' :
        #one day, when multi-method crossproduct indexes are supported...
        #if data['has_way_area'] :
        #    r=f"CREATE INDEX IF NOT EXISTS {data['name']} "
        #    return r+f"ON {data['table']} USING GIST({data['geom']}), GIN(way_area) {data['where']}"
        r=f"CREATE INDEX IF NOT EXISTS {data['name']} "
        return r+f"ON {data['table']} USING GIST({data['geom']}) {data['where']}"
    elif operation=='drop' :
        return f"DROP INDEX IF EXISTS {data['name']}"

def run_sql_indexes(c:psycopg2.extensions.cursor,sql_script:str,tmpl_defined:dict,command:str) :
    ''' Parse out indexes that could be useful from the compiled template sql_script.
    command: create -> CREATE INDEX IF NOT EXISTS
    command: drop -> DROP INDEX
    command: names -> return the index names as a list, do nothing else
    '''
    names=[]
    start=datetime.datetime.now()
    #collapse generator to get out error messages and flush the
    # annoying "applying array index offset" at the start
    payload=list(parse_indexed_create_unique(sql_script,tmpl_defined))
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
        while len(access.notices)>0 :
            line=access.notices.pop(0).strip().replace('\n','\n\t')
            print(line)
        print(command,d['name'],'in',(datetime.datetime.now()-start_one))
    if command=='names' :
        return names
    print(command,'all in',(datetime.datetime.now()-start))
    print(datetime.datetime.now(),'finished')

def run_sql_script(c:psycopg2.extensions.cursor,sql_script:str) :
    try :
        c.execute(sql_script)
    except psycopg2.errors.SyntaxError as err :
        if str(err).find('"AS"')>=0 :
            print(end='\033[31m')
            print('WARNING: Use a "_v" at end of template column name for omitting the "AS": eg {{polygon.boundary_v}} ')
            print('REMINDER: "_v" for the value of the column')
            print(end='\033[0m')
        raise err
    while len(access.notices)>0 :
        line=access.notices.pop(0).strip().replace('\n','\n\t')
        print(line)

def render_template_file(filename:str) :
    t=e.get_template(filename)
    return t.render()

def print_stats(c:psycopg2.extensions.cursor) :
    cols=[col.name for col in c.description]
    data=c.fetchall()
    print_table(data,cols)

def print_selected(c:psycopg2.extensions.cursor) :
    cols=[col.name for col in c.description]
    data=c.fetchone()
    print(dict(zip(cols,data)))

def print_table(data,headers) :
    if len(data)==0 :
        return
    maxwidths=[len(c) for c in headers]
    last_ix=len(maxwidths)-1
    for line in data :
        for ix,m in enumerate(maxwidths) :
            if len(str(line[ix]))>m :
                maxwidths[ix]=len(str(line[ix]))
    for ix,h in enumerate(headers) :
        print(' '+h.ljust(maxwidths[ix],' '),end=' |' if ix!=last_ix else '\n')
    for line in data :
        for ix,td in enumerate(line) :
            print(' '+str(td).ljust(maxwidths[ix],' '),end=' |' if ix!=last_ix else '\n')

def template_setup_languages(tmpl_defined,name_columns_languages) :
    tmpl_defined['make_name_columns_function']=len(name_columns_languages)!=0
    if tmpl_defined['make_name_columns_function'] :
        # utilities for the multiple name columns:
        ns=[] # names, for propagating up from a subquery
        nlls=[] # nulls as all names
        annl=[] # "any not null" boolean condition for "name_iso_a IS NOT NULL OR name_iso_b IS NOT NULL OR ..."
        ts=[] # typedefs for name_{lang} columns: everything is text
        #MAIN name_columns-generating sql :
        # everywhere: uses CASE WHEN name!=name_iso2 to make a little less data ("local" name always by default)
        # e.g. ("tags"->'name_en')='London' and "name"='London' will be exported as name_en=NULL and name='London'
        fns=[] # "~function~" to select the names correctly
        agns=[] #aggregate and run, names. aggregation version of the above fns

        agsqns=[] # aggregate from a qubquery, and propagate the aggregated values

        for iso2 in name_columns_languages:
            ns.append(f'"name_{iso2}",')
            nlls.append(f'NULL AS "name_{iso2}",')
            annl.append(f'"name_{iso2}" IS NOT NULL')
            ts.append(f'name_{iso2} text,')

            case_neq_name=f"\"tags\"->'name_{iso2}'"
            case_neq_name=f'CASE WHEN "name"!=({case_neq_name}) THEN {case_neq_name} ELSE NULL END'
            fns.append(f'({case_neq_name}) AS name_{iso2},')
            aggr=lambda i:f'(array_agg(DISTINCT ({i}) ORDER BY ({i}) NULLS LAST))[1] AS "name_{iso2}",'
            agns.append(aggr(case_neq_name))
            agsqns.append(aggr(f'"name_{iso2}"'))

        tmpl_defined['name_columns_run']=''.join(fns)
        tmpl_defined['name_columns_null']=''.join(nlls)
        tmpl_defined['name_columns_aggregate_run']=''.join(agns)
        tmpl_defined['name_columns_subquery_propagate']=''.join(ns)
        tmpl_defined['name_columns_subquery_aggregate_propagate']=''.join(agsqns)
        tmpl_defined['name_columns_typ']=''.join(ts)
        tmpl_defined['name_columns_any_notnull']=' OR '.join(annl)

def template_apply_args(tmpl_defined,args,c:psycopg2.extensions.cursor) :
    #global variables need_columns, aliases
    for k,v in make_global_dict(c,need_columns,aliases).items() :
        tmpl_defined[k]=v

    if hasattr(args,'languages') :
        template_setup_languages(tmpl_defined,args.languages)

    if hasattr(args,'with_osm_id') :
        tmpl_defined['with_osm_id']=args.with_osm_id
        tmpl_defined['poi_with_osm_id']=args.poi_with_osm_id
        tmpl_defined['place_with_osm_id']=args.place_with_osm_id

    if hasattr(args,'test_country_rel_id') :
        for k,v in zip(('test_z','test_x','test_y'),get_center_tile(c,-args.test_country_rel_id,12)) :
            tmpl_defined[k]=v

    if hasattr(args,'omt_typ_pref') :
        tmpl_defined['omt_typ_pref']=args.omt_typ_pref
        tmpl_defined['omt_func_pref']=args.omt_func_pref
        tmpl_defined['omt_all_func']=args.omt_all_func
    if hasattr(args,'omt_idx_pref') :
        tmpl_defined['omt_idx_pref']=args.omt_idx_pref

    return tmpl_defined


TEMPLATE_VARS={
    # transportation aggregates roads, remove osm_id if they are
    # "uninteresting", heuristic: for now just when name IS NULL.
    # only has an effect if with_osm_id=True
    'transportation_aggregate_osm_id_reduce':True,

    # if FALSE, name_columns_languages has no meaning and only "name" contains local name
    # if TRUE, "name" contains local name and "name_{iso2_code}" columns are added
    'make_name_columns_function':False,
    # avoid having to write {% if make_name_columns_function %}
    #   {{name_columns_run}} {% endif %} every time...
        #values for the default False
        'name_columns_typ':'',
        'name_columns_null':'',
        'name_columns_run':'',
        'name_columns_aggregate_run':'',
        'name_columns_subquery_propagate':'',
        'name_columns_subquery_aggregate_propagate':'',
        'name_columns_any_notnull':' false ',
    # WARNING: set to '' to ignore. else NEEDS to have a trailing comma
    # this is only added at the end, after the typedefed-rows have been
    #   generated. tags are not available anymore
    # for OSM-Bright: 'name AS "name:latin",',
    # but move away from name:latin and "just" add alias in JS
    'additional_name_columns':'',
    # other non-spec behaviour: the rank value is still filtering out items
    # on z>17 even though the spec says it SHOULD show all.
    # to force show all at z>=17, this workaround:
    'same_rank_poi_high_zooms':True,
    # name for the lake_centerlines loaded geojson data table (11MB size)
    'lake_table_name':'lake_centerline',
    # whether to add the "cycleway" column to layer "transportation". experimental and not in omt spec
    'transportation_with_cycleway':False,
    # tweak buffer size, extent or add other postgis args
    'bounds_geom_options':',extent=>4096,buffer=>(CASE WHEN z>=14 THEN 128 ELSE 64 END)',
}



if __name__=='__main__' :
    parser=argparse.ArgumentParser(prog='run.py')
    subparsers = parser.add_subparsers(title='subcommands',
        help='mode to choose, see "%(prog)s [mode] --help" for options')

    for action,action_help in {
        'create':'Create all functions, and replace them if they already exist',
        'index':'Create missing indexes to speedup functions',
        'index_drop':'Delete any present indexes',
        'lakes':'import lake_centerline data',
        'contours':'create contours_vector function (reads data from contours table)',
    }.items() :
        s=subparsers.add_parser(action, help=action_help)

        s.set_defaults(mode=action)
        #template configuration
        if action in ('create','contours') :
            s.add_argument('-r','--test-rel-id',dest='test_country_rel_id',
                default=51701,type=int,
                help="""Integer for the osm relation polygon in which to
                make the test tile, default Switzerland:%(default)s""")

        if action in ('create') :
            s.add_argument('--functions-prefix',dest='omt_func_pref',default='public.omt',type=str,
                help="""SQL prefix for function names, can include schema qualifier.
                Warning, --all-function does not use this prefix. Default '%(default)s'""")
            s.add_argument('--all-function-prefix',dest='omt_all_func',default='public.omt_all',type=str,
                help="""SQL name of complete-tile generating function, can include schema qualifier,
                default '%(default)s'""")
            s.add_argument('--typename-prefix',dest='omt_typ_pref',default='row_omt',type=str,
                help="""SQL prefix for all CREATE TYPE definitions, cannot include schema qualifier,
                default '%(default)s'""")
            s.add_argument('--with-osm-id',dest='with_osm_id',default=False,action='store_true',
                help="""Include osm_id data field in some layers: useful for map.on('click')
                    looking up of specific features.
                    Warning: can be a lot of additional data, default '%(default)s'""")
            s.add_argument('--poi-with-osm-id',dest='poi_with_osm_id',default=True,type=bool,
                help="""Include osm_id data field in poi layer, recommended for
                shop/restaurant/bus_stops lookups, default '%(default)s'""")
            s.add_argument('--place-with-osm-id',dest='place_with_osm_id',default=True,type=bool,
                help="""Include osm_id data field in place layer, recommended
                for villate/city/country lookups, default '%(default)s'""")

            s.add_argument('-l','--languages',dest='languages',default=['en','de','fr','ja','ar','ru'],type=list,
                help='''Which additional name_{lang} data fields to add.
                Specify empty list to only use local names, default "%(default)s"''')
        if action in ('index','index_drop') :
            s.add_argument('--index-prefix',dest='omt_idx_pref',default='planet_osm',type=str,
                help="""SQL prefix for all CREATE INDEX definitions, cannot include schema qualifier.
                Default '%(default)s'""")
        if action in ('create','index','lakes','contours') :
            s.add_argument('--print',dest='print',default=False,
                help='Instead of running them, print out SQL statements',
                action='store_true')

    parser.add_argument('-d','--dsn',dest='postgres_dsn',
        default='dbname=gis port=5432',
        help="The connection string to pass to psycopg2, default '%(default)s'")
    args=parser.parse_args()

    access=psycopg2.connect(args.postgres_dsn)
    c=access.cursor()
    e=jinja2.Environment(
        loader=jinja2.FileSystemLoader(os.path.dirname(__file__)),
    )
    e.globals=template_apply_args(TEMPLATE_VARS,args,c)

    sql_functions_script=render_template_file('omt-functions.sql')
    sql_contours_script=render_template_file('contours-function.sql')

    if args.mode=='create' :
        if args.print :
            print(sql_functions_script)
        else :
            run_sql_script(c,sql_functions_script)
            print('test tile',[e.globals['test_'+k] for k in 'zxy'])
            print_stats(c)
            c.execute('COMMIT;')

    elif args.mode=='index' :
        if args.print :
            for d in parse_indexed_create_unique(sql_functions_script,e.globals) :
                print(sql_index_command(d,'create'))
        else :
            access.commit()
            # WARN: enable transaction-less CREATE INDEX;
            access.autocommit=True
            run_sql_indexes(c,sql_functions_script,e.globals,'create')

    elif args.mode=='index_drop' :
        access.commit()
        # WARN: enable transaction-less CREATE INDEX;
        access.autocommit=True
        run_sql_indexes(c,sql_functions_script,e.globals,'drop')
    elif args.mode=='contours' :
        if args.print :
            print(sql_contours_script)
        else :
            run_sql_script(c,sql_contours_script)
            print('test tile',[e.globals['test_'+k] for k in 'zxy'])
            print_selected(c)
            c.execute('COMMIT;')
    elif args.mode=='lakes' :
        with open(os.path.dirname(__file__)+'/lake_centerline.geojson','r') as f :
            input_json=f.read()
        e.globals['input_json']=input_json
        sql_script=render_template_file('load_lake_centerline.sql')
        if args.print :
            print(sql_script)
        else :
            run_sql_script(c,sql_script)
            print_selected(c)
            c.execute('COMMIT;')
