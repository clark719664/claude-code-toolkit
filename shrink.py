import argparse
from PIL import Image
import os
import sys

def shrink_image(input_path, output_path=None, max_width=900, crop=None, gray=False):
    try:
        img = Image.open(input_path)
        orig_w, orig_h = img.size
        img = img.convert("RGB")
        
        if crop:
            left, top, right, bottom = map(int, crop.split(','))
            left = max(0, min(left, img.width))
            top = max(0, min(top, img.height))
            right = max(0, min(right, img.width))
            bottom = max(0, min(bottom, img.height))
            if (right - left) * (bottom - top) > 0:
                img = img.crop((left, top, right, bottom))
        
        if img.width > max_width:
            ratio = max_width / img.width
            new_height = int(img.height * ratio)
            img = img.resize((max_width, new_height), Image.LANCZOS)
        
        if gray:
            img = img.convert("L")
        
        if output_path is None:
            base, _ = os.path.splitext(input_path)
            output_path = base + "_small.png"
        
        img.save(output_path, format="PNG", optimize=True)

        old_size_kb = os.path.getsize(input_path) / 1024
        new_size_kb = os.path.getsize(output_path) / 1024

        # LLM image cost tracks PIXEL AREA, not file size: roughly (w*h)/750 tokens.
        old_tok = (orig_w * orig_h) // 750
        new_tok = (img.width * img.height) // 750
        print(f"{output_path} {orig_w}x{orig_h} ~{old_tok}tok ({old_size_kb:.0f}KB) -> "
              f"{img.width}x{img.height} ~{new_tok}tok ({new_size_kb:.0f}KB)  saves ~{old_tok-new_tok}tok/read")
        
    except FileNotFoundError:
        sys.stderr.write(f"Error: Input file '{input_path}' not found.\n")
        sys.exit(2)

def main():
    parser = argparse.ArgumentParser(description="Shrink a screenshot before it is read into an LLM context window.")
    parser.add_argument("INPUT", help="Input image path")
    parser.add_argument("-o", "--output", help="Output image path")
    parser.add_argument("--max-width", type=int, default=900, help="Maximum width of the output image")
    parser.add_argument("--crop", help="Crop area as L,T,R,B (comma-separated pixel coordinates)")
    parser.add_argument("--gray", action="store_true", help="Convert to grayscale")
    
    args = parser.parse_args()
    
    shrink_image(args.INPUT, args.output, args.max_width, args.crop, args.gray)

if __name__ == "__main__":
    main()
