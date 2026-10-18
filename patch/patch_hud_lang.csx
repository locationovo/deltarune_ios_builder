using System;
using System.IO;
using System.Linq;
using UndertaleModLib;
using UndertaleModLib.Decompiler;
using UndertaleModLib.Compiler;

if (Data == null) { Console.WriteLine("Data is null"); return; }
var ctx = new GlobalDecompileContext(Data);
var group = new CodeImportGroup(Data);

var langLoad = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_GlobalScript_scr_84_lang_load");
if (langLoad != null) {
    group.QueueReplace(langLoad, @"function scr_84_lang_load()
{
    var name = ""lang_ch1_cxkcxkckx_"" + global.lang + "".json"";
    var orig_filename = working_dir + ""lang/"" + name;
    var orig_map = scr_84_load_map_json(orig_filename);
    if (is_undefined(orig_map)) orig_map = scr_84_load_map_json(working_dir + ""games/lang/"" + name);
    if (is_undefined(orig_map) && global.lang == ""ja"") orig_map = scr_84_load_map_json(working_dir + ""games/lang/lang_ja.json"");
    if (is_undefined(orig_map) && global.lang == ""ja"") orig_map = scr_84_load_map_json(working_dir + ""lang/lang_ja.json"");
    if (is_undefined(orig_map)) orig_map = scr_84_load_map_json(working_dir + ""games/lang/lang_ch1_cxkcxkckx_en.json"");
    if (is_undefined(orig_map)) orig_map = ds_map_create();
    var new_filename = working_dir + ""lang-new/"" + name;
    var new_map = scr_84_load_map_json(new_filename);
    if (!is_undefined(new_map)) {
        var new_date = real(ds_map_find_value(new_map, ""date""));
        var orig_date = real(ds_map_find_value(orig_map, ""date""));
        if (new_date > orig_date) {
            ds_map_destroy(orig_map);
            orig_map = new_map;
        }
    }
    ds_map_destroy(global.lang_map);
    global.lang_map = orig_map;
    return ""loaded"";
}");
}

var getStr = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_GlobalScript_scr_84_get_lang_string");
if (getStr != null) {
    group.QueueReplace(getStr, @"function scr_84_get_lang_string(arg0)
{
    if (is_undefined(global.lang_map) || global.lang_map == -4) return string(arg0);
    var res = ds_map_find_value(global.lang_map, arg0);
    if (is_undefined(res)) return string(arg0);
    return res;
}");
}

var initDraw = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_Object_obj_initializer_Draw_0");
if (initDraw != null) {
    group.QueueReplace(initDraw, @"draw_set_color(random(60000));
if (variable_global_exists(""dbg_last_op"")) {
    var fnt = scr_84_get_font(""main"");
    if (font_exists(fnt)) { draw_set_font(fnt); } else { draw_set_font(-1); }
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_color(c_black);
    draw_set_alpha(0.6);
    draw_rectangle(10, 10, 450, 110, false);
    draw_set_alpha(1);
    draw_set_color(c_lime);
    var txt = ""FPS: "" + string(round(fps_real * 10) / 10) + ""\n"";
    txt += ""Room: "" + string(room) + ""\n"";
    txt += ""Op: "" + string(global.dbg_last_op);
    draw_text(20, 20, txt);
    draw_set_color(c_white);
}");
}

var dbgPrint = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_GlobalScript_scr_debug_print");
if (dbgPrint != null) {
    group.QueueReplace(dbgPrint, @"function scr_debug_print(arg0)
{
    global.dbg_last_op = string(arg0);
}");
}

group.Import();
