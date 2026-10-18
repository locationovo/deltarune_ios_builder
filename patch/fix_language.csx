using System;
using System.IO;
using System.Linq;
using UndertaleModLib;
using UndertaleModLib.Decompiler;
using UndertaleModLib.Compiler;

if (Data == null) { Console.WriteLine("Data is null"); return; }
var ctx = new GlobalDecompileContext(Data);
var group = new CodeImportGroup(Data);
int patched = 0;

void ReplaceFunction(string funcName, string newGml) {
    var code = Data.Code.FirstOrDefault(c => c.Name.Content == funcName);
    if (code != null) {
        group.QueueReplace(code, newGml);
        patched++;
    }
}

ReplaceFunction("gml_GlobalScript_scr_84_load_map_json", @"function scr_84_load_map_json(arg0)
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
}");

ReplaceFunction("gml_GlobalScript_scr_84_get_lang_string", @"function scr_84_get_lang_string(arg0)
{
    if (is_undefined(global.lang_map) || global.lang_map == -4) return string(arg0);
    var res = ds_map_find_value(global.lang_map, arg0);
    if (is_undefined(res)) return string(arg0);
    return res;
}");

var menuDraw = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_Object_DEVICE_MENU_Draw_0");
if (menuDraw != null) {
    string gml = new Underanalyzer.Decompiler.DecompileContext(ctx, menuDraw, Data.ToolInfo.DecompilerSettings).DecompileToString().Replace("\r\n", "\n");
    gml = gml.Replace("draw_set_font(fnt_ja_main);", "draw_set_font(fnt_main);");
    group.QueueReplace(menuDraw, gml);
    patched++;
}

group.Import();