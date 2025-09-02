--- **LibXML-1.0** Is a simple library for importing XML data into your WoW addon.
-- @class file
-- @name LibXML-1.0

--[[ LibXML-1.0

Revision: $Rev: 20 $
Author(s): Humbedooh
Description: XML import library
Dependencies: LibStub
License: MIT License

]]

--[===[@debug@
dofile([[..\LibStub\LibStub.lua]]);
_G.debugstack = function() return "AddOns\\Moo\\LibSVG-1.0.lua" end;
_G.GetBuildInfo = function() return "4.0.1", 13000, 0, 40000; end;
--@end-debug@]===]

local LIBXML = "LibXML-1.0"
local LIBXML_MINOR = tonumber(("$Rev: 020 $"):match("(%d+)")) or 10000;
if not LibStub then error(LIBXML .. " requires LibStub.") end
local LibXML = LibStub:NewLibrary(LIBXML, LIBXML_MINOR)
if not LibXML then return end

function LibXML.parseargs(s, l)
    local arg = {};
    for w,_,a in s:gmatch("([%w:%-]+)=([\"'])(.-)%2") do arg[w] = a end
    if l then for w,a in s:gmatch("([%w:%-]+)=([%w%.%-]+)") do arg[w] = a end end
    return arg;
end

function LibXML.at(s,e)
    local l = 1;
    for n = 1, e do if s:sub(n,n)=="\n" then l=l+1 end end
    return l
end

--- XML Import function
-- Imports the given XML string and returns a table structure containing the XML elements
-- @param xml_data The XML file (string) to be parsed.
-- @param loose_mode If set to <code>true</code>, LibXML will permit a looser syntax (optional)
-- @return <code>nil</code> if the XML is invalid, otherwise a table struct containing the XML elements
-- @return A message of any error encounted while parsing the XML data.
-- @usage
-- local xml_data = [[ <xml> <img src="some image URL" /> <p>Text goes here!<br/>And here!</p></xml> ]];
-- local libxml = LibStub("LibXML-1.0);
-- local struct, errmsg = libxml:Import(xml_data);
-- if ( errmsg ) then error(errmsg)
-- else
--     for i = 1, #struct do
--         local element = struct[i]
--         if ( element.class == "img" ) then ImageStuff(element.args.src) end
--         if ( element.class == "p" ) then
--             for j = 1, #element do
--                 local subElement = element[i]
--                 if ( type(subElement) == "string" ) then print(subElement) end
--                 if ( type(subElement) == "table" and subElement.class == "br" ) then
--                     print("We have a line break!\n");
--                 end
--             end
--         end
--     end
-- end
function LibXML:Import(s, loose)
    local tremove, parseargs,tinsert = table.remove, LibXML.parseargs,table.insert;
    local stack = {};
    local top = {};
    tinsert(stack, top);
    local ni,c,class,args,e;
    local i, j = 1, 1;
    while true do
        ni,j,c,class,args,e = s:find("<(%/?)([%-%w:]+)(.-)(%/?)>", i);
        if not ni then break end
        local text = s:sub(i, ni-1);
        if not text:find("^%s*$") then
            top[#top]=text;
        end
        if e == "/" or class:sub(1,1) == "!" then  -- empty element
            top[#top+1] ={class=class, args=parseargs(args, l), empty=true};
        elseif c == "" then   -- start tag
            top = {class=class, args=parseargs(args, l),ni=ni};
            stack[#stack+1] = top;   -- new level
        else  -- end tag
            local toclose = tremove(stack);  -- pop the top and get the opening tag
            top = stack[#stack];
            if #stack < 1 then
                return nil, ("%s: No opening tag found for <%s> at line %u!"):format(LIBXML, class, LibXML.at(s,ni));
            end
            if toclose.class ~= class then
                return nil, ("%s: Trying to close <%s> (at line %u) with </%s> (at line %u)!"):format(LIBXML, toclose.class, LibXML.at(s,toclose.ni), class, LibXML.at(s,ni));
            end
            top[#top+1] = toclose;
        end
        i = j+1;
    end
    local text = s:sub(i);
    if not text:find("^%s*$") then
        local st = stack[#stack];
        st[#st+1] = text;
    end
    if #stack > 1 then
        return nil, ("%s: XML data ended without closing <%s> (at line %u)!"):format(LIBXML, stack[#stack].class, stack[#stack].l);
    end
    return stack[1];
end


--[===[@debug@
local libxml = LibStub("LibXML-1.0");
local file = [[
<?xml version="1.1"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG December 1999//EN" "http://www.w3.org/Graphics/SVG/SVG-19991203.dtd" [
	<!ENTITY st0 "fill:#8C1788;stroke:none;">
	<!ENTITY st1 "fill:#202020;">
	<!ENTITY st2 "font-size:0.5;">
	<!ENTITY st3 "fill:#FF00FF;">
	<!ENTITY st4 "fill-rule:nonzero;fill:#FFFFFF;stroke:#000000;stroke-width:0.11677;stroke-miterlimit:10;">
	<!ENTITY st5 "fill:#CF4629;">
	<!ENTITY st6 "fill:none;stroke:none;">
	<!ENTITY st7 "font-family:'Helvetica';">
	<!ENTITY st8 "fill:#727272;">
	<!ENTITY st9 "fill:#0FF0FF;">
]>
<svg id="&st9;">
	<g/>
</svg>
]];
local struct = libxml:Import(file);
for n = 1, #struct do
	local el = struct[n];
	if ( type(el) == "table" ) then
		print(el, el.class, el.args.id);
	end
end
--@end-debug@]===]
