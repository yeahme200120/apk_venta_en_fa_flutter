"""
Quita el fondo blanco/claro de un PNG y lo guarda con canal alpha.
Uso: python remove_bg.py <entrada> <salida> [tolerancia]
Tolerancia 0-255: cuánto se aleja del blanco puro antes de considerarse "no fondo".
"""
import sys
from PIL import Image
import numpy as np

def remove_white_background(input_path: str, output_path: str, tolerance: int = 30):
    img = Image.open(input_path).convert("RGBA")
    data = np.array(img, dtype=np.float32)

    r, g, b, a = data[:,:,0], data[:,:,1], data[:,:,2], data[:,:,3]

    # Píxeles "blancos": los tres canales están cerca de 255
    is_white = (r >= (255 - tolerance)) & (g >= (255 - tolerance)) & (b >= (255 - tolerance))

    # Hacer flood-fill desde las 4 esquinas para solo eliminar fondo exterior
    # (no borrar blancos internos del logo, como el hueco del carrito)
    from PIL import ImageDraw
    mask = Image.fromarray(is_white.astype(np.uint8) * 255, mode="L")
    
    # Seed flood-fill: esquinas de la imagen
    flood = Image.new("L", img.size, 0)
    draw = ImageDraw.Draw(flood)
    w, h = img.size
    seeds = [(0,0), (w-1,0), (0,h-1), (w-1,h-1)]
    
    # Expandir desde esquinas usando BFS
    from collections import deque
    visited = np.zeros((h, w), dtype=bool)
    white_arr = is_white
    queue = deque()
    for sx, sy in seeds:
        if not visited[sy, sx]:
            visited[sy, sx] = True
            if white_arr[sy, sx]:
                queue.append((sx, sy))
    
    while queue:
        x, y = queue.popleft()
        for dx, dy in [(-1,0),(1,0),(0,-1),(0,1)]:
            nx, ny = x+dx, y+dy
            if 0 <= nx < w and 0 <= ny < h and not visited[ny,nx] and white_arr[ny,nx]:
                visited[ny,nx] = True
                queue.append((nx, ny))
    
    # Solo los píxeles blancos alcanzados desde las esquinas se hacen transparentes
    result = np.array(img)
    result[visited, 3] = 0  # alpha = 0 (transparente)
    
    out = Image.fromarray(result, mode="RGBA")
    out.save(output_path, "PNG")
    print(f"Guardado: {output_path}  ({w}x{h}px, tolerancia={tolerance})")

if __name__ == "__main__":
    inp = sys.argv[1]
    out = sys.argv[2]
    tol = int(sys.argv[3]) if len(sys.argv) > 3 else 30
    remove_white_background(inp, out, tol)
