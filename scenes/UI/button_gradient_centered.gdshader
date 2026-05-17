shader_type canvas_item;

// --- EXPORTED VARIABLES ---
// These will appear in the Godot Inspector automatically!
uniform vec4 color_dark : source_color = vec4(0.1, 0.1, 0.15, 0.6);
uniform vec4 color_light : source_color = vec4(0.2, 0.5, 0.9, 1.0);
uniform int step_count = 6;                 // How many color levels from center to edge
uniform float center_ratio = 0.3;             // How much of the element the darkest center step occupies (0.0 to 1.0)

void fragment() {
    // Turn UV.x into distance from the center.
    // 0.0 = dead middle (darkest), 1.0 = either edge (brightest).
    float dist_from_center = abs(UV.x - 0.5) * 2.0;
    
    // Make sure we never divide by zero
    float safe_steps = float(max(step_count, 2));
    float effective_center = clamp(center_ratio, 0.0, 1.0);
    
    // --- THE STEPPING MATH ---
    float stepped_pos;
    
    if (dist_from_center < effective_center || effective_center >= 1.0) {
        // Inside the wide center band — darkest step
        stepped_pos = 0.0;
    } else {
        // Remaining distance outside the center, split evenly into the other steps
        float virtual_pos = (dist_from_center - effective_center) / (1.0 - effective_center);
        
        // +1 because step 0 is the center band we already handled
        float step_index = floor(virtual_pos * (safe_steps - 1.0) + 1.0);
        
        // Clamp so the outermost edge never overshoots
        step_index = min(step_index, safe_steps - 1.0);
        
        stepped_pos = step_index / (safe_steps - 1.0);
    }
    
    // --- APPLY COLOR ---
    vec4 final_color = mix(color_dark, color_light, stepped_pos);
    COLOR = final_color;
}
