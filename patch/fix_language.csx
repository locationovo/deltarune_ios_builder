using System;
using System.IO;
using System.Linq;
using UndertaleModLib;
using UndertaleModLib.Decompiler;
using UndertaleModLib.Compiler;

if (Data == null) { return; }
GlobalDecompileContext ctx = new GlobalDecompileContext(Data);
CodeImportGroup group = new CodeImportGroup(Data);

var code1 = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_GlobalScript_scr_84_load_map_json");
if (code1 != null) {
    string gml1 = @"function scr_84_load_map_json(arg0)
{
    var file_buffer = -1;
    try { file_buffer = buffer_load(arg0); } catch (_e) {}
    if (file_buffer != -1 && buffer_get_size(file_buffer) > 0)
    {
        var json = buffer_read(file_buffer, buffer_string);
        buffer_delete(file_buffer);
        var result = json_decode(json);
        if (is_undefined(result)) return ds_map_create();
        return result;
    }
    if (file_buffer != -1) buffer_delete(file_buffer);
    return ds_map_create();
}";
    group.QueueReplace(code1, gml1);
}

var code2 = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_GlobalScript_scr_84_get_lang_string");
if (code2 != null) {
    string gml2 = @"function scr_84_get_lang_string(arg0)
{
    if (is_undefined(global.lang_map) || global.lang_map == -4) return string(arg0);
    var res = ds_map_find_value(global.lang_map, arg0);
    if (is_undefined(res)) return string(arg0);
    return res;
}";
    group.QueueReplace(code2, gml2);
}

group.Import();