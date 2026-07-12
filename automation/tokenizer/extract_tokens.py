import os
import re
import json
import argparse

def extract_swift_tokens(swift_file_path):
    with open(swift_file_path, 'r') as f:
        content = f.read()

    tokens = {
        "colors": {},
        "typography": {},
        "icon_sizes": {}
    }

    # Extract AppColors
    app_colors_match = re.search(r'enum AppColors\s*{(.*?)}', content, re.DOTALL)
    if app_colors_match:
        app_colors_content = app_colors_match.group(1)
        
        # Matches: static let backgroundPrimary = Color(red: 0.05, green: 0.07, blue: 0.06)
        color_matches = re.finditer(r'static let (\w+) = Color\(red: ([\d.]+), green: ([\d.]+), blue: ([\d.]+)\)', app_colors_content)
        for match in color_matches:
            name, r, g, b = match.groups()
            tokens["colors"][name] = {
                "r": float(r),
                "g": float(g),
                "b": float(b)
            }
            
        # Matches: static let border = Color.white.opacity(0.06)
        opacity_matches = re.finditer(r'static let (\w+) = Color\.(\w+)\.opacity\(([\d.]+)\)', app_colors_content)
        for match in opacity_matches:
            name, base_color, opacity = match.groups()
            tokens["colors"][name] = {
                "base_color": base_color,
                "opacity": float(opacity)
            }

    # Extract AppTypography
    app_typography_match = re.search(r'enum AppTypography\s*{(.*?)}', content, re.DOTALL)
    if app_typography_match:
        app_typography_content = app_typography_match.group(1)
        
        typo_matches = re.finditer(r'static let (\w+):\s*Font\s*=\s*\.system\(\.(\w+)(?:,\s*design:\s*\.(\w+))?(?:,\s*weight:\s*\.(\w+))?\)', app_typography_content)
        for match in typo_matches:
            name, size, design, weight = match.groups()
            tokens["typography"][name] = {
                "size": size,
                "design": design if design else "default",
                "weight": weight if weight else "regular"
            }

    # Extract AppIconSize
    app_icon_size_match = re.search(r'enum AppIconSize\s*{(.*?)}', content, re.DOTALL)
    if app_icon_size_match:
        app_icon_size_content = app_icon_size_match.group(1)
        
        icon_size_matches = re.finditer(r'static let (\w+):\s*Font\s*=\s*\.system\(\.(\w+)\)', app_icon_size_content)
        for match in icon_size_matches:
            name, size = match.groups()
            tokens["icon_sizes"][name] = {
                "size": size
            }

    return tokens

def extract_asset_colors(assets_dir):
    colors = {}
    if not os.path.exists(assets_dir):
        return colors

    for root, dirs, files in os.walk(assets_dir):
        if root.endswith('.colorset') and 'Contents.json' in files:
            color_name = os.path.basename(root).replace('.colorset', '')
            with open(os.path.join(root, 'Contents.json'), 'r') as f:
                data = json.load(f)
                color_modes = {}
                for color_info in data.get('colors', []):
                    mode = 'light'
                    if 'appearances' in color_info:
                        for app in color_info['appearances']:
                            if app.get('appearance') == 'luminosity' and app.get('value') == 'dark':
                                mode = 'dark'
                    
                    color_val = color_info.get('color', {})
                    if 'components' in color_val:
                        comps = color_val['components']
                        if 'red' in comps and 'green' in comps and 'blue' in comps:
                            color_modes[mode] = {
                                'red': comps['red'],
                                'green': comps['green'],
                                'blue': comps['blue']
                            }
                            if 'alpha' in comps:
                                color_modes[mode]['alpha'] = comps['alpha']
                                
                if color_modes:
                    colors[color_name] = color_modes
    return colors

def main():
    parser = argparse.ArgumentParser(description="Extract design tokens to JSON schema")
    parser.add_argument('--design-system', type=str, default='Sources/DesignSystem/DesignSystem.swift', help='Path to DesignSystem.swift')
    parser.add_argument('--assets', type=str, default='Sources/Assets.xcassets', help='Path to Assets.xcassets')
    parser.add_argument('--output', type=str, default='design_tokens.json', help='Output JSON file path')
    
    args = parser.parse_args()

    tokens = {}
    
    # 1. Swift tokens
    if os.path.exists(args.design_system):
        print(f"Extracting tokens from: {args.design_system}")
        swift_tokens = extract_swift_tokens(args.design_system)
        tokens.update(swift_tokens)
    else:
        print(f"Warning: DesignSystem.swift not found at '{args.design_system}'. Check the path.")

    # 2. Asset catalog colors
    if os.path.exists(args.assets):
        print(f"Extracting asset colors from: {args.assets}")
        asset_colors = extract_asset_colors(args.assets)
        tokens["asset_colors"] = asset_colors
    else:
        print(f"Warning: Assets.xcassets not found at '{args.assets}'. Check the path.")

    # 3. Write output
    output_dir = os.path.dirname(args.output)
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir)
        
    with open(args.output, 'w') as f:
        json.dump(tokens, f, indent=2)
    
    print(f"Successfully generated token schema at: {args.output}")

if __name__ == '__main__':
    main()
