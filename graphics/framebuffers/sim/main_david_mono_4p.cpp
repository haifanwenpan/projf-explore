// Project F: Framebuffers - Mono David Verilator C++
// (C)2023 Will Green, open source software released under the MIT License
// Learn more at https://projectf.io/posts/framebuffers/

#include <stdio.h>
#include <SDL.h>
#include <verilated.h>
#include "Vtop_david_mono_4p.h"

// screen dimensions
const int H_RES = 640;
const int V_RES = 480;

typedef struct Pixel {  // for SDL texture
    uint8_t a;  // transparency
    uint8_t b;  // blue
    uint8_t g;  // green
    uint8_t r;  // red
} Pixel;

int main(int argc, char* argv[]) {
    Verilated::commandArgs(argc, argv);

    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        printf("SDL init failed.\n");
        return 1;
    }

    Pixel screenbuffer[H_RES*V_RES];

    SDL_Window*   sdl_window   = NULL;
    SDL_Renderer* sdl_renderer = NULL;
    SDL_Texture*  sdl_texture  = NULL;

    sdl_window = SDL_CreateWindow("Mono David", SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED, H_RES, V_RES, SDL_WINDOW_SHOWN);
    if (!sdl_window) {
        printf("Window creation failed: %s\n", SDL_GetError());
        return 1;
    }

    sdl_renderer = SDL_CreateRenderer(sdl_window, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!sdl_renderer) {
        printf("Renderer creation failed: %s\n", SDL_GetError());
        return 1;
    }

    sdl_texture = SDL_CreateTexture(sdl_renderer, SDL_PIXELFORMAT_RGBA8888,
        SDL_TEXTUREACCESS_TARGET, H_RES, V_RES);
    if (!sdl_texture) {
        printf("Texture creation failed: %s\n", SDL_GetError());
        return 1;
    }

    // reference SDL keyboard state array: https://wiki.libsdl.org/SDL_GetKeyboardState
    const Uint8 *keyb_state = SDL_GetKeyboardState(NULL);

    printf("Simulation running. Press 'Q' in simulation window to quit.\n\n");

    // initialize Verilog module
    Vtop_david_mono_4p* top = new Vtop_david_mono_4p;

    // reset
    top->rst_pix = 1;
    top->clk_pix = 0;
    top->eval();
    top->clk_pix = 1;
    top->eval();
    top->rst_pix = 0;
    top->clk_pix = 0;
    top->eval();

    uint64_t frame_count = 0;
    uint64_t start_ticks = SDL_GetPerformanceCounter();
    while (1) {
        // cycle the clock
        top->clk_pix = 1;
        top->eval();
        top->clk_pix = 0;
        top->eval();

        // update pixel if not in blanking interval
        if (top->sdl_de) {
            Pixel* p0 = &screenbuffer[top->sdl_sy*H_RES + top->sdl_sx*4];
            p0->a = 0xFF;  // transparency
            p0->b = top->sdl_b0;
            p0->g = top->sdl_g0;
            p0->r = top->sdl_r0;
            Pixel* p1 = &screenbuffer[top->sdl_sy*H_RES + top->sdl_sx*4+1];
            p1->a = 0xFF;  // transparency
            p1->b = top->sdl_b1;
            p1->g = top->sdl_g1;
            p1->r = top->sdl_r1;
            Pixel* p2 = &screenbuffer[top->sdl_sy*H_RES + top->sdl_sx*4+2];
            p2->a = 0xFF;  // transparency
            p2->b = top->sdl_b2;
            p2->g = top->sdl_g2;
            p2->r = top->sdl_r2;
            Pixel* p3 = &screenbuffer[top->sdl_sy*H_RES + top->sdl_sx*4+3];
            p3->a = 0xFF;  // transparency
            p3->b = top->sdl_b3;
            p3->g = top->sdl_g3;
            p3->r = top->sdl_r3;
        }

        // update texture once per frame (in blanking)
        if (top->sdl_frame) {
            // check for quit event
            SDL_Event e;
            if (SDL_PollEvent(&e)) {
                if (e.type == SDL_QUIT) {
                    break;
                }
            }

            if (keyb_state[SDL_SCANCODE_Q]) break;  // quit if user presses 'Q'

            SDL_UpdateTexture(sdl_texture, NULL, screenbuffer, H_RES*sizeof(Pixel));
            SDL_RenderClear(sdl_renderer);
            SDL_RenderCopy(sdl_renderer, sdl_texture, NULL, NULL);
            SDL_RenderPresent(sdl_renderer);
            frame_count++;
        }
    }
    uint64_t end_ticks = SDL_GetPerformanceCounter();
    double duration = ((double)(end_ticks-start_ticks))/SDL_GetPerformanceFrequency();
    double fps = (double)frame_count/duration;
    printf("Frames per second: %.1f\n", fps);

    top->final();  // simulation done

    SDL_DestroyTexture(sdl_texture);
    SDL_DestroyRenderer(sdl_renderer);
    SDL_DestroyWindow(sdl_window);
    SDL_Quit();
    return 0;
}
