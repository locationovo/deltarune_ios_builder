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

var code = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_GlobalScript_scr_84_get_lang_string");
if (code != null) {
    group.QueueReplace(code, @"function scr_84_get_lang_string(arg0)
{
    if (is_undefined(global.lang_map) || global.lang_map == -4) return string(arg0);
    var res = ds_map_find_value(global.lang_map, arg0);
    if (is_undefined(res)) return string(arg0);
    return res;
}");
    patched++;
}

var menuDraw = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_Object_DEVICE_MENU_Draw_0");
if (menuDraw != null) {
    string gml = new Underanalyzer.Decompiler.DecompileContext(ctx, menuDraw, Data.ToolInfo.DecompilerSettings).DecompileToString().Replace("\r\n", "\n");
    gml = gml.Replace("draw_set_font(fnt_ja_main);", "draw_set_font(fnt_main);");
    group.QueueReplace(menuDraw, gml);
    patched++;
}

group.Import();
Console.WriteLine("  [fix_language] Total patched: " + patched);