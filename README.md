# MASM Mandelbrot Viewer

An interactive viewer of the famous Mandelbrot fractal that is primarily coded in assembly with MASM as the assembler. Uses C++ and SFML as a program wrapper and window manager.

Extensively utilizes SSE SIMD instructions in order to parallelize the escape-time computation as well as the generation of the pixel data for the fractal image.

Supports zooming, panning, adjusting escape iteration count, and changing color modes.

Video presentation: https://youtu.be/cNKODLQ0vBc 

![Preview Image](/mandelbrot-readme-img.png)
