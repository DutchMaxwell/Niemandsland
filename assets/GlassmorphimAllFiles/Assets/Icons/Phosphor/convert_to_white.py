import os
import re

# Directory containing the SVG files
dir_path = r'C:/Users/plata/Documents/Godot/AudaciousAtelierGodotTutorials/Audacious-Atelier-Godot-Tutorials/Assets/Icons/Phosphor/'

def change_fill_to_white(svg_path):
    """
    Change all fill attributes in an SVG file to pure white (#FFFFFF).
    This handles both fill="currentColor" and fill="#000000" etc.
    """
    try:
        with open(svg_path, 'r', encoding='utf-8') as file:
            content = file.read()
        
        # Replace any fill attribute with fill="#FFFFFF" (pure white)
        # This regex finds fill="anything" and replaces it with fill="#FFFFFF"
        updated_content = re.sub(r'fill="[^"]*"', 'fill="#FFFFFF"', content)
        
        # Only write if content changed
        if updated_content != content:
            with open(svg_path, 'w', encoding='utf-8') as file:
                file.write(updated_content)
            print(f"✓ Updated: {os.path.basename(svg_path)}")
            return True
        else:
            print(f"- No changes needed: {os.path.basename(svg_path)}")
            return False
            
    except Exception as e:
        print(f"✗ Failed to update {os.path.basename(svg_path)}: {e}")
        return False

def main():
    """Main function to process all SVG files"""
    print("🔄 Starting SVG color conversion to pure white...")
    print(f"📁 Directory: {dir_path}")
    print("-" * 50)
    
    if not os.path.exists(dir_path):
        print(f"❌ Directory not found: {dir_path}")
        return
    
    # Get all SVG files, excluding dot and line-vertical files
    exclude_patterns = ['dot-', 'line-vertical']
    svg_files = []
    
    for f in os.listdir(dir_path):
        if f.endswith('.svg'):
            # Check if the file should be excluded
            excluded = False
            for pattern in exclude_patterns:
                if pattern in f.lower():
                    excluded = True
                    break
            
            if not excluded:
                svg_files.append(f)
    
    if not svg_files:
        print("❌ No SVG files found in the directory")
        return
    
    print(f"📊 Found {len(svg_files)} SVG files (excluding dot and line-vertical files)")
    print("-" * 50)
    
    updated_count = 0
    
    # Process each SVG file
    for filename in svg_files:
        svg_file = os.path.join(dir_path, filename)
        if change_fill_to_white(svg_file):
            updated_count += 1
    
    print("-" * 50)
    print(f"✅ Complete! Updated {updated_count} out of {len(svg_files)} files")

if __name__ == "__main__":
    main()
