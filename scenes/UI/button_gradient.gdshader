shader_type canvas_item;

// --- EXPORTED VARIABLES ---
// These will appear in the Godot Inspector automatically!
// : source_color gives you a nice Color Picker wheel instead of raw numbers.
uniform vec4 color_dark : source_color = vec4(0.1, 0.1, 0.15, 0.6); // Dark greyish-blue, slightly transparent
uniform vec4 color_light : source_color = vec4(0.2, 0.5, 0.9, 1.0); // Bright saturated blue, fully opaque
uniform int step_count = 6; // How many 8px increments you want
uniform bool is_selected = false; // The switch our GDScript will flip

void fragment() {
    // UV.x gives us a smooth line from 0.0 (left edge) to 1.0 (right edge)
    float gradient_pos = UV.x;
    
    // If the button is selected/focused, we invert the direction
    if (is_selected) {
        gradient_pos = 1.0 - gradient_pos; 
    }
    
    // --- THE MAGIC MATH ---
    // Make sure we never divide by zero if you accidentally type 1 or 0 in the editor
    float safe_steps = float(max(step_count, 2));
    
    // Step 1: Multiply the 0.0->1.0 line by the number of steps (e.g., 6) -> Range is now 0.0 to 6.0
    // Step 2: floor() chops off the decimals. So a smooth ramp becomes chunky steps: 0, 1, 2, 3, 4, 5
    // Step 3: Divide by (steps - 1) to squash those chunks back down to a 0.0 -> 1.0 scale.
    float stepped_pos = floor(gradient_pos * safe_steps) / (safe_steps - 1.0);
    
    // --- APPLY COLOR ---
    // mix() blends the dark and light colors based on our chunky steps.
    // Because vec4 contains RGBA, this perfectly steps the transparency (Alpha) as well!
    vec4 final_color = mix(color_dark, color_light, stepped_pos);
    
    // Set the pixel to our final color
    COLOR = final_color;
}