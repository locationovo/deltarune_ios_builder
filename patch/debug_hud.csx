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

var initObj = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_Object_obj_initializer_Create_0");
if (initObj != null) {
    string gml = new Underanalyzer.Decompiler.DecompileContext(ctx, initObj, Data.ToolInfo.DecompilerSettings).DecompileToString().Replace("\r\n", "\n");
    string initCode = @"
global.dbg_last_op = """";
if (object_exists(obj_debug_gui)) {
    if (!instance_exists(obj_debug_gui)) {
        var dbg = instance_create_depth(0, 0, -9999, obj_debug_gui);
        dbg.persistent = true;
    }
}
";
    group.QueueReplace(initObj, gml + "\n" + initCode);
    patched++;
}

var hudDraw = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_Object_obj_debug_gui_Draw_64");
if (hudDraw != null) {
    group.QueueReplace(hudDraw, @"
var gw = window_get_width();
var gh = window_get_height();
if (gw <= 0) gw = display_get_gui_width();
if (gh <= 0) gh = display_get_gui_height();
if (gw <= 0 || gh <= 0) exit;

draw_set_font(-1);
draw_set_halign(fa_right);
draw_set_valign(fa_top);
draw_set_color(c_black);
draw_set_alpha(0.55);
draw_rectangle(gw - 600, 0, gw, 200, false);
draw_set_alpha(1);
draw_set_color(c_lime);

var str = ""FPS: "" + string(round(fps_real * 10) / 10);
str += ""\nRoom: "" + string(room);
if (variable_global_exists(""dbg_last_op"") && global.dbg_last_op != """") {
    str += ""\nOp: "" + string(global.dbg_last_op);
}
draw_text(gw - 20, 20, str);
draw_set_halign(fa_left);
draw_set_valign(fa_top);
draw_set_color(c_white);
");
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