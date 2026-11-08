-- Run from repository root: lua test/lua/graph_test.lua
json=dofile('test/lua/json.lua')
local env=setmetatable({json=json},{__index=_G})
assert(loadfile('src/lua/compile-graph.lua','t',env))()
local modules={}
local function importer(path) return assert(modules[path],'missing module '..path) end
env.import=importer
local function compile(text)
 local result=env.main({graphJson=text})
 local runtime=setmetatable({json=json,import=importer},{__index=_G})
 return assert(load(result.source,'@graph.ng.lua','t',runtime))(),result
end
local raw='[{"id":1,"kind":4,"name":"value","inputs":[],"outputs":[{"id":1,"name":"n","value":"3"}]},{"id":2,"kind":2,"name":"double","codePath":"double.lua","inputs":[{"id":1,"name":"n","srcNodeId":1,"srcOutputId":1}],"outputs":[{"id":1,"name":"result","value":null}]},{"id":3,"kind":1,"name":"goal","inputs":[{"id":1,"name":"answer","srcNodeId":2,"srcOutputId":1}],"outputs":[]}]'
modules['double.lua']=function(inputs,outputs) outputs[1]=inputs.n*2 end
local graph,result=compile(raw)
assert(result.diagnostic==json.null,result.diagnostic)
assert(graph.ng_graph_json()==raw)
assert(graph.main().goal.inputs.answer==6)
modules['double.lua']={run=function(inputs,outputs) outputs[1]=inputs.n*4 end}
assert(graph.main().goal.inputs.answer==12)
modules['double.lua']=function(_,outputs) outputs.active[1]=false end
assert(graph.main().goal.active.answer==false)
local broken,bad=compile('[{"id":1,"kind":77,"name":"bad","inputs":[],"outputs":[]}]')
assert(type(bad.diagnostic)=='string' and bad.diagnostic:find('unknown node kind'))
assert(broken.ng_graph_json():find('77'))
assert(not pcall(broken.main))
local linked='[{"id":1,"kind":3,"name":"group","storage":{"mode":"linked","path":"child.ng.lua"},"inputs":[],"outputs":[{"id":9,"name":"out","value":null}]},{"id":2,"kind":1,"name":"goal","inputs":[{"id":1,"name":"answer","srcNodeId":1,"srcOutputId":9}],"outputs":[]}]'
local function child(n)
 return {ng_graph_json=function() return '{"format":"gams-group-graph","version":1,"nodes":[{"id":8,"kind":4,"name":"value","inputs":[],"outputs":[{"id":1,"name":"n","value":"'..n..'"}]},{"id":9,"kind":6,"name":"out","inputs":[{"id":1,"name":"value","srcNodeId":8,"srcOutputId":1}],"outputs":[]}]}' end,ng_graph_import=importer}
end
modules['child.ng.lua']=child(7)
local parent=compile(linked)
assert(parent.main().goal.inputs.answer==7)
modules['child.ng.lua']=child(11)
assert(parent.main().goal.inputs.answer==11)
print('graph Lua tests passed')
local function encode(v)
 if v==json.null then return 'null' end
 if type(v)=='string' then return '"'..v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n')..'"' end
 if type(v)~='table' then return tostring(v) end
 local out={}
 if #v>0 or next(v)==nil then for _,x in ipairs(v) do out[#out+1]=encode(x) end; return '['..table.concat(out,',')..']' end
 for k,x in pairs(v) do out[#out+1]=encode(k)..':'..encode(x) end
 return '{'..table.concat(out,',')..'}'
end
local function input(id,name,node,port) return {id=id,name=name,srcNodeId=node or 0,srcOutputId=port or 0} end
local function output(id,name,value) return {id=id,name=name,value=value or json.null} end
local function node(id,kind,inputs,outputs) return {id=id,kind=kind,name='n'..id,inputs=inputs or {},outputs=outputs or {}} end
local initializations=0
modules['init.lua']=function(inputs,outputs) initializations=initializations+1; outputs[1]=inputs[1] end
modules['sum.lua']=function(inputs,outputs)
 outputs[1]=inputs.total+inputs.item
 outputs[2]=inputs.item==2
 outputs[3]=inputs.item==3
end
local initializer=node(17,2,{input(1,'initial',16,1)},{output(1,'initial')}); initializer.codePath='init.lua'
local sum=node(13,2,{input(1,'total',12,1),input(2,'item',10,1)},{output(1,'sum'),output(2,'skip'),output(3,'break')}); sum.codePath='sum.lua'
local loop=node(2,7,{input(10,'items',1,1),input(16,'initial',3,1)},{output(20,'collected'),output(30,'total')})
loop.outputs[2].stateNodeId=12; loop.outputs[2].statePortId=1
loop.childGraph={
 node(10,8,{}, {output(1,'Item'),output(2,'Index'),output(3,'Array')}),
 node(16,10,{}, {output(1,'Value')}),initializer,
 node(12,11,{input(1,'total',17,1)},{output(1,'total')}),sum,
 node(14,12,{input(1,'total',13,1)}),
 node(15,9,{input(1,'Skip',13,2),input(2,'Break',13,3)}),
 node(20,6,{input(1,'value',13,1)})
}
local loopGraph={node(1,4,{}, {output(1,'array','[1,2,3,4]')}),node(3,4,{}, {output(1,'initial','0')}),loop,node(4,1,{input(1,'items',2,20),input(2,'total',2,30)})}
local executable,compiled=compile(encode(loopGraph))
assert(compiled.diagnostic==json.null,compiled.diagnostic)
local result=executable.main().n4.inputs
assert(initializations==1 and result.total==6 and #result.items==1 and result.items[1]==1)
-- Empty loops still initialize and return state and an empty array.
loopGraph[1].outputs[1].value='[]'
local empty=compile(encode(loopGraph))
result=empty.main().n4.inputs
assert(result.total==0 and #result.items==0 and initializations==2)
-- Active nil state updates are errors, not silently retained previous values.
modules['sum.lua']=function(_,outputs) outputs[2]=false; outputs[3]=false end
local ok,err=pcall(executable.main)
assert(not ok and tostring(err):find('active nil update'))
print('For Each state/control tests passed')
-- Inline Group Graph Input/Output aliases preserve false and branch activity.
local group=node(40,3,{input(41,'in',1,1)},{output(42,'out')})
group.storage={mode='inline'}
group.childGraph={node(41,5,{}, {output(1,'value')}),node(42,6,{input(1,'value',41,1)})}
local inline=compile(encode({node(1,4,{}, {output(1,'false','false')}),group,node(2,1,{input(1,'value',40,42)})}))
assert(inline.main().n2.inputs.value==false and inline.main().n2.active.value)
-- Linked cycles reject canonical relative aliases, independent of import caching.
local cyclic=linked:gsub('child.ng.lua','./child.ng.lua')
modules['child.ng.lua']={ng_graph_json=function() return cyclic end,ng_graph_import=importer}
modules['./child.ng.lua']=modules['child.ng.lua']
local invalid,diagnostic=compile(cyclic)
assert(diagnostic.diagnostic:find('alias cycle'))
assert(not pcall(invalid.main))
-- Missing/malformed code modules are save diagnostics, never missing metadata.
modules['double.lua']={}
local unfinished,badModule=compile(raw)
assert(badModule.diagnostic:find('Code module'))
assert(unfinished.ng_graph_json()==raw)
print('Group alias/validation tests passed')
