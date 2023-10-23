
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

// add this: document.map.on('load',set_name_property);

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
