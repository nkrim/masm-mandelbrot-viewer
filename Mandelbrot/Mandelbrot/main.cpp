#include <SFML/Graphics.hpp>

#include <iostream>
#include <vector>

extern "C" {
	sf::Uint8* mandelbrot_get_frame_pointer();
	sf::Uint8* mandelbrot_frame_generator(double, double, double, __int32, __int32);
}

const unsigned MAX_ITERATIONS = 256;
const unsigned MANDELBROT_WIDTH = 512;
const unsigned MANDELBROT_HEIGHT = 512;

/*const std::vector<sf::Color> color_map{
	sf::Color(0x7A3815FF), sf::Color(0xE3FCFCFF)//, 0x06072DFF, 0x7A3815FF
};

void mandelbrot(sf::Texture& tex, double x_center, double y_center, double scale, double scale_exp, unsigned max_iterations)
{
	double x0 = (x_center - 1.235*scale) - 0.765;
	double y0 = (y_center - 1.12*scale);
	double width = 2.47*scale;
	double height = 2.24*scale;
	sf::Vector2u tex_size = tex.getSize();
	sf::Uint8* pixel_array = new sf::Uint8[4 * tex_size.x * tex_size.y];
	double x_delta = width / tex_size.x;
	double y_delta = height / tex_size.y;
	unsigned pa_index = 0;
	double y_base = y0;
	for(unsigned i_y=0; i_y<tex_size.y; i_y++)
	{
		double x_base = x0;
		for(unsigned i_x=0; i_x<tex_size.x; i_x++)
		{
			unsigned iter_count = 0;
			double x = x_base;
			double y = y_base;
			double x_sqr = x_base*x_base;
			double y_sqr = y_base*y_base;
			for(; x_sqr+y_sqr<=32 && iter_count<max_iterations; iter_count++) 
			{
				double x_temp = x_sqr - y_sqr + x_base;
				y = (x+x)*y + y_base;
				x = x_temp;

				x_sqr = x*x;
				y_sqr = y*y;
			}

			// calculate color
			//iter_count &= 0b11;
			//unsigned __int32 color_32 = 0xFF;
			if(iter_count < max_iterations) {
				// from wikipedia https://en.wikipedia.org/wiki/Plotting_algorithms_for_the_Mandelbrot_set#Continuous_(smooth)_coloring
				// sqrt of inner term removed using log simplification rules.
				//long double log_of_2 = logl(2.0);
				//long double log_zn = logl(x_sqr + y_sqr) / 2;
				//long double nu = logl(log_zn / log_of_2) / log_of_2;
				
				// fancy interpolated color number copied from https://www.reddit.com/r/math/comments/2abwyt/smooth_colour_mandelbrot/
				double v = log(iter_count + 1.5 - log2(log(sqrt(x_sqr+y_sqr)))) / 3.4;

				// !!! THE CURSED LINES !!!
				//v *= log(height/2.24);
				//v += log(height/2.24);
				// !! THE CURSED LINES !!!

				if(v < 1.0) {
					pixel_array[pa_index+3] = 0xFF;
					pixel_array[pa_index+2] = (sf::Uint8)(v*255);
					pixel_array[pa_index+1] = (sf::Uint8)((v*=v)*255);
					pixel_array[pa_index+0] = (sf::Uint8)((v*=v)*255);
					pa_index += 4;
				}
				else {
					v = fmaxl(0.0, 2.0 - v);
					pixel_array[pa_index+3] = 0xFF;
					pixel_array[pa_index+2] = (sf::Uint8)(powl(v,3)*255);
					pixel_array[pa_index+1] = (sf::Uint8)(powl(v,1.5)*255);
					pixel_array[pa_index+0] = (sf::Uint8)(v*255);
					pa_index += 4;
				}
			}
			else {
				pixel_array[pa_index++] = 0;
				pixel_array[pa_index++] = 0;
				pixel_array[pa_index++] = 0;
				pixel_array[pa_index++] = 0xFF;
			}

			// increment x of point
			x_base += x_delta;
		}
		// increment y of point
		y_base += y_delta;
	}

	// load pixel array into texture
	tex.update(pixel_array);
	return;
}*/

int main()
{
	sf::Uint8* pixel_data = mandelbrot_get_frame_pointer();
	
	sf::RenderWindow window(sf::VideoMode(MANDELBROT_WIDTH, MANDELBROT_HEIGHT), "Mandelbrot Viewer");

	// setup Mandelbrot texture and sprite
	sf::Texture mandelbrot_texture;
	mandelbrot_texture.create(MANDELBROT_WIDTH, MANDELBROT_HEIGHT);
	//mandelbrot_texture.update((sf::Uint8*)pixel_data);
	//mandelbrot_texture.setSmooth(true);
	sf::Sprite mandelbrot_sprite(mandelbrot_texture);

	double x_center = 0;//0.0044555899367317957;//0;
	double y_center = 0;//-0.13822593998657223;//0;
	double scale = 1.0;//0.0089338206101794732;// 1.0;
	double scale_exp = 0;

	__int32 max_iterations = MAX_ITERATIONS;
	double time_since_last_mi_change = 0;

	__int32 color_mode_index = 0;

	sf::Clock clock;

	while(window.isOpen())
	{
		double t = std::min(0.5, (double)clock.restart().asSeconds());
		double t_scale = t*scale;
		time_since_last_mi_change += t;

		sf::Event event;
		while(window.pollEvent(event))
		{
			if(event.type == sf::Event::Closed)
				window.close();
		}

		// key inputs
		// - lateral movements
		if(sf::Keyboard::isKeyPressed(sf::Keyboard::A))
			x_center -= t_scale;
		if(sf::Keyboard::isKeyPressed(sf::Keyboard::D))
			x_center += t_scale;
		if(sf::Keyboard::isKeyPressed(sf::Keyboard::W))
			y_center -= t_scale;
		if(sf::Keyboard::isKeyPressed(sf::Keyboard::S))
			y_center += t_scale;
		// - zooming 
		if(sf::Keyboard::isKeyPressed(sf::Keyboard::Up) || sf::Keyboard::isKeyPressed(sf::Keyboard::Equal))
			scale_exp += t;
		if(sf::Keyboard::isKeyPressed(sf::Keyboard::Down) || sf::Keyboard::isKeyPressed(sf::Keyboard::Hyphen))
			scale_exp = std::max(0.0, scale_exp-t);
		// - iteration adjustment
		if(time_since_last_mi_change > 0.5) {
			if(sf::Keyboard::isKeyPressed(sf::Keyboard::Left)) {
				max_iterations = std::max(32, max_iterations>>1);
				time_since_last_mi_change = 0;
			}
			if(sf::Keyboard::isKeyPressed(sf::Keyboard::Right)) {
				max_iterations = std::min(2048, max_iterations<<1);
				time_since_last_mi_change = 0;
			}
		}
		// - color mode
		if(sf::Keyboard::isKeyPressed(sf::Keyboard::Num1)) {
			color_mode_index = 0;
		}
		if(sf::Keyboard::isKeyPressed(sf::Keyboard::Num2)) {
			color_mode_index = 1;
		}
		if(sf::Keyboard::isKeyPressed(sf::Keyboard::Num3)) {
			color_mode_index = 2;
		}
		if(sf::Keyboard::isKeyPressed(sf::Keyboard::Num8) && sf::Keyboard::isKeyPressed(sf::Keyboard::Num9)) {
			color_mode_index = 0x30;
		}
		else if(sf::Keyboard::isKeyPressed(sf::Keyboard::Num8)) {
			color_mode_index = 0x10;
		}
		else if(sf::Keyboard::isKeyPressed(sf::Keyboard::Num9)) {
			color_mode_index = 0x20;
		}
		// - reset
		if(sf::Keyboard::isKeyPressed(sf::Keyboard::R) || sf::Keyboard::isKeyPressed(sf::Keyboard::Num0)) {
			x_center = 0;
			y_center = 0;
			scale_exp = 0;
			max_iterations = MAX_ITERATIONS;
			time_since_last_mi_change = 0;
		}

		// call assembly to generate mandelbrot
		scale = exp2(-scale_exp);
		mandelbrot_frame_generator(x_center, y_center, scale, max_iterations, color_mode_index);
		mandelbrot_texture.update(pixel_data);
		//mandelbrot(mandelbrot_texture, x_center, y_center, scale, scale_exp, max_iterations);

		window.clear();
		window.draw(mandelbrot_sprite);
		window.display();
	}

	return 0;
}