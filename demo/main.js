function popup_text(f) {
  var p=f.properties;
  p['map_layer']=f.sourceLayer;
  return Object.keys(p).map(k=>k+'='+p[k]).join('<br>');
}

function enable_contours() {
  // append contours to current map
  fetch('styles/contours.json').then(r=>r.json()).then(function(c) {
    Object.keys(c.sources).forEach(k=>{
        document.map.addSource(k,c.sources[k]);
    });
    c.layers.forEach(l=>document.map.addLayer(l));
  });
  //enable contourscheckbox 
  var chb=document.querySelector('#contourscheckbox');
  chb.disabled=false;
  chb.checked=true;
  chb.onchange=function (e) {
    console.log(e);
    var setVis='none';
    if (chb.checked) {
        setVis='visible';
    }
    ['contours10','contours50','contours100'].forEach(function(cl) {
      document.map.setLayoutProperty(cl,'visibility',setVis);
    });
  };
}
function enable_tilebounds_checkbox() {
  // enable tileboundscheckbox
  var tbc=document.querySelector('#tileboundscheckbox');
  tbc.disabled=false;
  tbc.checked=false;
  tbc.onchange=function (e) {
    document.map.showTileBoundaries=tbc.checked;
  };
}

function add_geojson_playground() {
  // can be re-added without wiping data
  // add geojson playground layer
  if (document.playground_data==null) {
    document.playground_data={
      type:'FeatureCollection',
      features:[]
    };
  }
  document.map.addSource('playground',{
    type:'geojson',
    data:document.playground_data
  });
  document.map.addLayer({
    id: 'playground_fill_layer',
    type: 'fill',
    filter: [ '==', '$type', 'Polygon' ],
    source: 'playground',
    paint: {
      'fill-color':'#ff00ff',
      'fill-antialias':true,
      'fill-outline-color':'#ff00ff',
      'fill-opacity':0.05
    }
  });
  document.map.addLayer({
    id: 'playground_line_layer',
    type: 'line',
    filter: [ '==', '$type', 'LineString' ],
    source: 'playground',
    paint: {
      'line-color':'#ff00ff'
    }
  });
}

function get_centerpoint(g) {
  console.log('center',g);
  if (g.type=='Point') {
    return g.coordinates;
  } else if (g.type=='Polygon') {
    // average of all points, WARN: weighed 1!
    var res=[0,0];
    var count=0;
    g.coordinates[0].forEach(pt=>{
      res[0]+=pt[0];
      res[1]+=pt[1];
      count+=1;
    });
    return [res[0]/count,res[1]/count];
  } else if (g.type=='MultiPolygon') {
      var maxlen=0;
      var result_poly_coords;
      g.coordinates.forEach(ar=>{
        if (ar[0].length>maxlen) {
          maxlen=ar[0].length;
          result_poly_coords=ar[0];
        }
      });
      return get_centerpoint({type:'Polygon',coordinates:[result_poly_coords]});
  } else if (g.type=='MultiLineString') {
      var maxlen=0;
      var result_poly_coords;
      g.coordinates.forEach(ar=>{
        if (ar.length>maxlen) {
          maxlen=ar.length;
          result_poly_coords=ar;
        }
      });
      return get_centerpoint({type:'LineString',coordinates:result_poly_coords});
  } else if (g.type=='LineString') {
    var avg_point=get_centerpoint({type:'Polygon',coordinates:[g.coordinates]});
    var min_sq_dist=1e30;
    var closest_point=g.coordinates[0];
    g.coordinates.forEach(pt=>{
      if (pt_sq_dist(pt,avg_point)<min_sq_dist) {
        min_sq_dist=pt_sq_dist(pt,avg_point);
        closest_point=pt;
      }
    });
    return closest_point;
  }
}

function pt_sq_dist(a,b) {
  return (a[0]-b[0])*(a[0]-b[0])+(a[1]-b[1])*(a[1]-b[1]);
}

function replace_recursive_prop(subject,source,target) {
  // any-type subject style property: replace source with target.
  // for object and list types, descend recursively while keeping
  // everything else the same
  if (typeof(subject)=='number'||typeof(subject)=='boolean') {
    return subject;
  } else if (typeof(subject)=='string') {
    return subject.replaceAll(source,target);
  } else if (Array.isArray(subject)) {
    return subject.map((i)=>replace_recursive_prop(i,source,target));
  }
  Object.keys(subject).forEach(k=>{
    subject[k]=replace_recursive_prop(subject[k],source,target);
  });
  return subject;
}

function set_name_property() {
  // go through style and change every occurence of "name:latin" to "name"
  document.map.getStyle().layers.forEach(l=>{
    if (l.layout!=null && l.layout['text-field']!=null) {
      //console.log(l.id,'orig=',JSON.stringify(l.layout['text-field']));
      var new_prop=replace_recursive_prop(l.layout['text-field'],'name:latin','name');
      //console.log('new=',JSON.stringify(new_prop));
      document.map.setLayoutProperty(l.id,'text-field',new_prop);
    }
  });
}

function add_click_listener() {
  var map_layers_ordering=['poi','mountain_peak','park','place','boundary',
      'aerodrome_label','aeroway','housenumber','building','water_name','water',
      'transportation_name','transportation','waterway','landuse','landcover'];
  document.map.on('click',(e)=> {
    console.log('clicked');
    var feature_ix=map_layers_ordering.length;
    var selected_feature=null;
    document.map.queryRenderedFeatures(e.point).forEach((f)=>{
      var curr_ix=map_layers_ordering.indexOf(f.sourceLayer);
      if (f.source=='playground') {
        return;
      }
      if (curr_ix<feature_ix) {
        feature_ix=curr_ix;
        selected_feature=f;
      }
    });
    if (selected_feature==null) {
      return;
    }
    var f=selected_feature;
    document.playground_data.features.push(f);

    var pp=new maplibregl.Popup();
    pp.setLngLat(get_centerpoint(f.geometry)).setHTML(popup_text(f)).addTo(document.map);
    document.map.getSource('playground').setData(document.playground_data);
  });
}

function add_relief() {
  document.map.addSource('terrarium',{
      "type": "raster-dem",
      "tiles": [
        "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
      ],
      "minzoom": 0,
      "maxzoom": 15,
      "tileSize": 256,
      "encoding": "terrarium"
  });
  document.map.addLayer({
    "id": "terrain-rgb",
    "source": "terrarium",
    "type": "hillshade",
    "paint": {
      "hillshade-shadow-color": "hsl(39, 21%, 33%)",
      "hillshade-illumination-direction": 315,
      "hillshade-exaggeration": 0.8
    }
  });
}

function enable_style_selector() {
  var st=document.querySelector('#styleselector');
  document.styles.forEach((s,s_ix)=> {
    var op=document.createElement('option');
    op.name=s_ix;
    op.innerHTML=s.name;
    op.value=s.href;
    st.appendChild(op);
  });
  st.onchange=(ev)=>{
    switch_style_over(st.selectedIndex);
  };
}

function switch_style_over(tgt_index) {
  document.map.setStyle(document.styles[tgt_index].href);
  document.map.on('styledata',()=>{
    // warning: triggers multiple times at each style data load
    console.log('concurrency issue just below: but just ignore it!...');
    if (document.map.getSource('contours')==null) {
      enable_contours();
    }
    if (document.map.getSource('playground')==null) {
      add_geojson_playground();
    }
    set_name_property(); // assume everything uses "name:latin" in the style
  });
}

function main() {
  document.styles=[
    // take the first as default on load
    {name:'OpenStreetMap Carto',href:'demo/styles/openstreetmap-vector.json'},
    {name:'OSM Bright',href:'demo/styles/osm-bright.json'},
    {name:'MapTiler Basic',href:'demo/styles/maptiler-basic.json'},
    {name:'OSM Bright cyclo',href:'demo/styles/cyclo-bright.json'},
  ];
  try {
    document.map = new maplibregl.Map({
      container: 'map',
      style: document.styles[0].href, // stylesheet location
      // weiningen, zurich, switzerland
      center: [8.43,47.42],
      zoom: 15,
      // show # in url, when copying the url the lat,lon,zoom,tilt,rotation position is included
      hash: true,
    });
  } catch (err) {
    try {
      var displ_msg=JSON.parse(err.message).message.toString();
    } catch (err2) {
      var displ_msg=err.toString();
    }
    document.querySelector('p#loading').innerHTML=displ_msg;
    alert(displ_msg);
  }
  document.map.on('load',function() {
    set_name_property();
    document.querySelector('p#loading').remove();
    enable_contours();
    enable_tilebounds_checkbox();
    enable_style_selector();

    //add_relief();

    add_geojson_playground();
    // depends on geojson playground
    add_click_listener();
  });
}

main();
