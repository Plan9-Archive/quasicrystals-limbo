implement Quasi;

include "sys.m";
include "draw.m";
include "math.m";
include "string.m";
include "tk.m";
include "tkclient.m";
include "arg.m";

sys: Sys;
draw: Draw;
	Display, Rect, Image: import draw;
math: Math;
	atan2, cos, floor, log, sin, sqrt, Degree, Pi: import math;
str: String;
tk: Tk;
tkclient: Tkclient;
arg: Arg;

Quasi: module {
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

Point: adt
{
	x: real;
	y: real;
};

display: ref Display;
top: ref Tk->Toplevel;

size := 200;
zoom := 3;
scale := 30.;
ws := 5;

time := 0;

taskcfg := array[] of {
	"panel .c",
	"pack .c -fill both -expand 1",
};

init(ctxt: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	math = load Math Math->PATH;
	str = load String String->PATH;
	arg = load Arg Arg->PATH;
	
	arg->init(args);
	args = arg->argv();
	if(len args == 4) {
		i := 0;
		for(; args != nil; args = tl args) {
			case i {
			0 => size = int hd args;
			1 => zoom = int hd args;
			2 => scale = real hd args;
			3 => ws = int hd args;
			}
			i++;
		}
	}
	sys->print("(size %d) (zoom %d) (scale %g) (degree %d)\n", size, zoom, scale, ws);

	spawn window(ctxt);
}

window(ctxt: ref Draw->Context)
{
	tk = load Tk Tk->PATH;
	tkclient = load Tkclient Tkclient->PATH;

	tkclient->init();
	display = ctxt.display;
	
	titlectl: chan of string;
	(top, titlectl) = tkclient->toplevel(ctxt, "", "Quasicrystals", Tkclient->Appl);
	
	cmdch := chan of string;
	tk->namechan(top, cmdch, "cmd");
	
	for (i := 0; i < len taskcfg; i++)
		tkcmd(top, taskcfg[i]);
	
	start := sys->millisec();
	img := frame(size, zoom, ws, 0);
	stop := sys->millisec();
	sys->print("%dms\n", stop-start);
	tk->putimage(top, ".c", img, nil);
	tkcmd(top, "pack propagate . 0");
	tkcmd(top, "update");
	tkclient->onscreen(top, nil);
	tkclient->startinput(top, "kbd"::"ptr"::nil);
	
	sync := chan of int;
	step := chan of ref Image;
	spawn animate(size, zoom, ws, step, sync);
	apid := <- sync;
	
	for(;;) alt {
	s := <-top.ctxt.kbd =>
		tk->keyboard(top, s);
	s := <-top.ctxt.ptr =>
		tk->pointer(top, *s);
	c := <-top.ctxt.ctl or
	c = <-top.wreq or
	c = <-titlectl =>
		if(c == "exit") {
			kill(apid);
			return;
		}
		e := tkclient->wmctl(top, c);
		if(e == nil && c[0] == '!'){
			kill(apid);
			spawn animate(actr(".c").dy(), zoom, ws, step, sync);
			apid = <- sync;
		}

	img = <-step =>
		stop = sys->millisec();
		tk->putimage(top, ".c", img, nil);
		tkcmd(top, "update");
		#sys->print("%dms\n", stop-start);
		start=stop;
	}
}

animate(sz, z, deg: int, c: chan of ref Image, p: chan of int)
{
	p <-= sys->pctl(Sys->NEWPGRP, nil);
	
	for(;;) {
		c <-= frame(sz, z, deg, time++);
	}
}

point(x, y: int): Point
{
	denom := real size - 1.0;
	X := scale * ((real(2*x)/denom) - 1.0);
	Y := scale * ((real(2*y)/denom) - 1.0);
		
	return Point(X, Y);
}

transform(θ: real, p: Point): Point
{
	p.x = p.x * cos(θ) - p.y * sin(θ);
	p.y = p.x * sin(θ) + p.y * cos(θ);
	return p;
}

wave1(ϕ, θ: real, p: Point): real
{
	if(θ != 0.0)
		p = transform(θ, p);
	return (cos(ϕ+p.y) + 1.) / 2.0;
}

wave(ϕ, θ: real, p: Point): real
{
	if(θ != 0.0)
		p = transform(θ, p);
	return (cos(cos(ϕ)*p.x + sin(ϕ)*p.y) + 1.0) / 2.0;
}

quasicrystal(size, degree: int, ϕ: real): array of array of byte
{
	buf := array[size] of { * => array[size] of byte};
	
	for (y := 0; y < size; y++){
		for (x := 0; x < size; x++){
			θ := 0. * Degree;
			#θ := atan2(real x, real y) + ϕ;
			#θ := atan2(real x + ϕ, real y + ϕ) + ϕ;
			p := point(x,y);
			acc := wave1(ϕ, θ, p);
			for (d := 1; d < degree; d++) {
				θ += 180. * Degree / real degree;
				if(d%2)
					acc += 1. - wave(ϕ, θ, p);
				else
					acc += wave(ϕ, θ, p);
			}
			buf[y][x] = byte (acc * 255.0);
		}
	}
	
	return buf;
}

frame(sz: int, z: int, deg: int, time: int): ref Image
{
	ϕ := real time * 5.0 * Degree;
	
	q := quasicrystal(sz, deg, ϕ);
	
	img := top.display.newimage(((0,0), (sz*z,sz*z)), Draw->GREY8, 0, Draw->Black);
	buf := array[sz*z] of byte;
	for (y := 0; y < sz; y++) {
		for (x := 0; x < sz; x++) {
			pixel := array[z] of { * => q[y][x]};
			buf[x*z:] = pixel[0:z];
		}
		for (i := 0; i < z; i++)
			img.writepixels(((0,y*z+i), (sz*z,y*z+i+1)), buf);
	}
		
	return img;
}

actr(w: string): Rect
{
	r: Rect;
	bd := int tkcmd(top, w + " cget -bd");
	r.min.x = int tkcmd(top, w + " cget -actx") + bd;
	r.min.y = int tkcmd(top, w + " cget -acty") + bd;
	r.max.x = r.min.x + int tkcmd(top, w + " cget -actwidth");
	r.max.y = r.min.y + int tkcmd(top, w + " cget -actheight");
	return r;
}

tkcmd(top: ref Tk->Toplevel, cmd: string): string
{
	e := tk->cmd(top, cmd);
	if (e != nil && e[0] == '!')
		sys->print("quasi: tk error on '%s': %s\n", cmd, e);
	return e;
}

hexdump(b: array of byte): string
{
	s := "";
	for(i:=0; i<len b; i++) {
		if(i%16 == 0)
			s = s + "\n\t";
		s = sys->sprint("%s %02X", s, int(b[i]));
	}
	
	return str->drop(s, "\n");
}

progctl(pid: int, s: string)
{
	f := sys->sprint("/prog/%d/ctl", pid);
	fd := sys->open(f, Sys->OWRITE);
	sys->fprint(fd, "%s", s);
}

kill(pid: int)
{
	progctl(pid, "kill");
}