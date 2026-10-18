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
global.dbg_last_op = ""Boot"";
if (!instance_exists(obj_debug_gui)) {
    var dbg = instance_create_depth(0, 0, -9999, obj_debug_gui);
    dbg.persistent = true;
}
";
    group.QueueReplace(initObj, gml + "\n" + initCode);
    patched++;
}

var dbgDraw = Data.Code.FirstOrDefault(c => c.Name.Content == "gml_Object_obj_debug_gui_Draw_64");
if (dbgDraw != null) {
    string hud = @"
draw_set_font(fnt_main);
draw_set_halign(fa_right);
draw_set_valign(fa_top);
var w = display_get_gui_width();
var h = display_get_gui_height();
var str = ""FPS: "" + string(fps_real) + ""\nRoom: "" + string(room) + ""\nMem: "" + string(gc_get_stats(gc_stat_heap_size));
if (variable_global_exists(""dbg_last_op"")) {
    str += ""\nOp: "" + global.dbg_last_op;
}
draw_set_alpha(0.7);
draw_set_color(c_black);
draw_rectangle(w - 280, 0, w, 100, false);
draw_set_alpha(1);
draw_set_color(c_lime);
draw_text(w - 10, 10, str);
draw_set_halign(fa_left);
draw_set_valign(fa_top);
draw_set_color(c_white);
";
    group.QueueReplace(dbgDraw, hud);
    patched++;
}

group.Import();