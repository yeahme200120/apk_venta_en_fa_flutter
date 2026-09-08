"""
Toma el logo PNG transparente y lo centra en un canvas cuadrado 1024x1024
listo para flutter_launcher_icons.
"""
from PIL import Image
import sys

def make_square(input_path: str, output_path: str, size: int = 1024, padding_pct: float = 0.12):
    img = Image.open(input_path).convert("RGBA")
    w, h = img.size

    # Determinar el tamaño del logo dentro del canvas con padding
    inner = int(size * (1 - padding_pct * 2))
    ratio = min(inner / w, inner / h)
    new_w = int(w * ratio)
    new_h = int(h * ratio)
    img_resized = img.resize((new_w, new_h), Image.LANCZOS)

    # Canvas transparente
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    x = (size - new_w) // 2
    y = (size - new_h) // 2
    canvas.paste(img_resized, (x, y), img_resized)
    canvas.save(output_path, "PNG")
    print(f"Ícono guardado: {output_path}  ({size}x{size}px, logo {new_w}x{new_h}px)")

if __name__ == "__main__":
    inp = sys.argv[1]
    out = sys.argv[2]
    sz  = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
    make_square(inp, out, sz)
