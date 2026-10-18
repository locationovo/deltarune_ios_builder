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
    draw_rectangle(10, 10, 350, 110, false);
    draw_set_alpha(1);
    draw_set_color(c_lime);
    var txt = ""FPS: "" + string(round(fps_real * 10) / 10) + ""\n"";
    txt += ""Room: "" + string(room) + ""\n"";
    txt += ""Op: "" + string(global.dbg_last_op);
    draw_text(20, 20, txt);
    draw_set_color(c_white);
}");
    patched++;
}

var dbgPrint = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_GlobalScript_scr_debug_print");
if (dbgPrint != null) {
    group.QueueReplace(dbgPrint, @"function scr_debug_print(arg0)
{
    global.dbg_last_op = string(arg0);
}");
    patched++;
}

group.Import();
Console.WriteLine("  [debug_hud] Total patched: " + patched);