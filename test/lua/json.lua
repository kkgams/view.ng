-- Dependency-free JSON decoder used by the native graph evaluator tests.
local M={null={}}
local array={}
function M.array() return setmetatable({},array) end
function M.object() return {} end
function M.is_array(t) return getmetatable(t)==array end
function M.decode(text)
 local i=1
 local function space() local _,e=text:find('^[ \t\r\n]*',i); i=(e or i-1)+1 end
 local parse
 local function string_value()
  assert(text:sub(i,i)=='"'); i=i+1; local out={}
  while i<=#text do
   local c=text:sub(i,i); i=i+1
   if c=='"' then return table.concat(out) end
   if c=='\\' then
    c=text:sub(i,i); i=i+1
    local escape={['"']='"',['\\']='\\',['/']='/',n='\n',r='\r',t='\t',b='\b',f='\f'}
    if c=='u' then c=utf8.char(assert(tonumber(text:sub(i,i+3),16))); i=i+4 else c=assert(escape[c]) end
   end
   out[#out+1]=c
  end
  error('unterminated JSON string')
 end
 parse=function()
  space(); local c=text:sub(i,i)
  if c=='"' then return string_value() end
  if c=='[' or c=='{' then
   i=i+1; local out=c=='[' and M.array() or {}; local close=c=='[' and ']' or '}'; space()
   if text:sub(i,i)==close then i=i+1; return out end
   while true do
    local key=#out+1
    if c=='{' then space(); key=string_value(); space(); assert(text:sub(i,i)==':'); i=i+1 end
    out[key]=parse(); space(); local sep=text:sub(i,i); i=i+1
    if sep==close then return out end
    assert(sep==',','expected comma')
   end
  end
  for literal,v in pairs({['true']=true,['false']=false,['null']=M.null}) do
   if text:sub(i,i+#literal-1)==literal then i=i+#literal; return v end
  end
  local num=text:match('^-?%d+%.?%d*[eE]?[+-]?%d*',i)
  assert(num and tonumber(num),'invalid JSON at '..i); i=i+#num; return tonumber(num)
 end
 local result=parse(); space(); assert(i>#text,'trailing JSON'); return result
end
return M
