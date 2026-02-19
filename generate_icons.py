"""
Generate all FoxCloud icon variants from the main icon.ico.
Run: python generate_icons.py
"""
from PIL import Image, ImageOps
import os

BASE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(BASE, "assets", "images")
WIN_RES = os.path.join(BASE, "windows", "runner", "resources")
ANDROID_RES = os.path.join(BASE, "android", "app", "src", "main", "res")
MACOS_ASSETS = os.path.join(BASE, "macos", "Runner", "Assets.xcassets", "AppIcon.appiconset")

def load_icon():
    """Load the main icon.ico as RGBA."""
    ico_path = os.path.join(ASSETS, "icon.ico")
    img = Image.open(ico_path)
    img = img.convert("RGBA")
    # Get largest size from ICO
    if hasattr(img, 'n_frames') and img.n_frames > 1:
        # Try to get the largest frame
        best = img
        for i in range(img.n_frames):
            img.seek(i)
            if img.size[0] > best.size[0]:
                best = img.copy()
        img = best
    # Ensure we have a decent size
    if img.size[0] < 512:
        img = img.resize((512, 512), Image.LANCZOS)
    return img


def make_white_version(img):
    """Create a white (light) version - white silhouette from alpha channel."""
    r, g, b, a = img.split()
    # Create white image with same alpha
    white = Image.new("RGBA", img.size, (255, 255, 255, 0))
    white.putalpha(a)
    return white


def make_black_version(img):
    """Create a black (dark) version - black silhouette from alpha channel."""
    r, g, b, a = img.split()
    black = Image.new("RGBA", img.size, (0, 0, 0, 0))
    black.putalpha(a)
    return black


def make_stop_version(img):
    """Create a 'stop' version - dimmed/semi-transparent version."""
    r, g, b, a = img.split()
    # Reduce alpha by 50%
    a = a.point(lambda x: x // 2)
    result = Image.merge("RGBA", (r, g, b, a))
    return result


def save_png(img, path, size=None):
    """Save as PNG, optionally resizing."""
    if size:
        img = img.resize((size, size), Image.LANCZOS)
    img.save(path, "PNG")
    print(f"  Saved: {os.path.basename(path)} ({img.size[0]}x{img.size[1]})")


def save_ico(img, path, sizes=None):
    """Save as ICO with multiple sizes."""
    if sizes is None:
        sizes = [256, 128, 64, 48, 32, 16]
    imgs = []
    for s in sizes:
        resized = img.resize((s, s), Image.LANCZOS)
        imgs.append(resized)
    imgs[0].save(path, format="ICO", sizes=[(s, s) for s in sizes])
    print(f"  Saved: {os.path.basename(path)} (sizes: {sizes})")


def generate_assets_images(icon):
    """Generate all icon variants in assets/images/."""
    print("\n=== assets/images/ ===")
    
    white = make_white_version(icon)
    black = make_black_version(icon)
    stop_white = make_stop_version(white)
    stop_black = make_stop_version(black)
    
    # PNGs (512x512)
    save_png(icon, os.path.join(ASSETS, "icon.png"), 512)
    save_png(white, os.path.join(ASSETS, "icon_white.png"), 512)
    save_png(black, os.path.join(ASSETS, "icon_black.png"), 512)
    save_png(stop_white, os.path.join(ASSETS, "icon_stop_white.png"), 512)
    save_png(stop_black, os.path.join(ASSETS, "icon_stop_black.png"), 512)
    
    # ICOs (multi-size)
    tray_sizes = [64, 48, 32, 16]
    save_ico(icon, os.path.join(ASSETS, "icon.ico"))
    save_ico(white, os.path.join(ASSETS, "icon_white.ico"), tray_sizes)
    save_ico(black, os.path.join(ASSETS, "icon_black.ico"), tray_sizes)
    save_ico(stop_white, os.path.join(ASSETS, "icon_stop_white.ico"), tray_sizes)
    save_ico(stop_black, os.path.join(ASSETS, "icon_stop_black.ico"), tray_sizes)


def generate_windows_icon(icon):
    """Generate Windows app icon."""
    print("\n=== windows/runner/resources/ ===")
    os.makedirs(WIN_RES, exist_ok=True)
    save_ico(icon, os.path.join(WIN_RES, "app_icon.ico"))


def generate_android_icons(icon):
    """Generate Android launcher icons for all densities."""
    print("\n=== android mipmap icons ===")
    
    # Standard Android mipmap sizes
    densities = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    
    for folder, size in densities.items():
        folder_path = os.path.join(ANDROID_RES, folder)
        os.makedirs(folder_path, exist_ok=True)
        save_png(icon, os.path.join(folder_path, "ic_launcher.png"), size)
    
    # Also generate notification icon (white silhouette)
    white = make_white_version(icon)
    drawable_densities = {
        "drawable-mdpi": 24,
        "drawable-hdpi": 36,
        "drawable-xhdpi": 48,
        "drawable-xxhdpi": 72,
        "drawable-xxxhdpi": 96,
    }
    
    for folder, size in drawable_densities.items():
        folder_path = os.path.join(ANDROID_RES, folder)
        if os.path.exists(folder_path):
            # Check if there's an ic.png (notification icon)
            ic_path = os.path.join(folder_path, "ic.png")
            if os.path.exists(ic_path):
                save_png(white, ic_path, size)

    # TV banner (320x180)
    banner_densities = {
        "mipmap-xhdpi": (320, 180),
    }
    for folder, (w, h) in banner_densities.items():
        folder_path = os.path.join(ANDROID_RES, folder)
        banner_path = os.path.join(folder_path, "ic_banner.png")
        if os.path.exists(banner_path):
            # Create banner: icon centered on dark background
            banner = Image.new("RGBA", (w, h), (32, 32, 32, 255))
            icon_small = icon.resize((h - 20, h - 20), Image.LANCZOS)
            offset = ((w - icon_small.width) // 2, 10)
            banner.paste(icon_small, offset, icon_small)
            banner.save(banner_path, "PNG")
            print(f"  Saved: {folder}/ic_banner.png ({w}x{h})")


def generate_macos_icons(icon):
    """Generate macOS app icon set."""
    print("\n=== macOS AppIcon.appiconset ===")
    if not os.path.exists(MACOS_ASSETS):
        print("  macOS icon assets directory not found, skipping")
        return
    
    macos_sizes = {
        "app_icon_16.png": 16,
        "app_icon_32.png": 32,
        "app_icon_64.png": 64,
        "app_icon_128.png": 128,
        "app_icon_256.png": 256,
        "app_icon_512.png": 512,
        "app_icon_1024.png": 1024,
    }
    for name, size in macos_sizes.items():
        path = os.path.join(MACOS_ASSETS, name)
        if os.path.exists(path):
            save_png(icon, path, size)


def main():
    print("FoxCloud Icon Generator")
    print("=" * 40)
    
    icon = load_icon()
    print(f"Loaded icon: {icon.size[0]}x{icon.size[1]} {icon.mode}")
    
    generate_assets_images(icon)
    generate_windows_icon(icon)
    generate_android_icons(icon)
    generate_macos_icons(icon)
    
    print("\n✅ All icons generated!")


if __name__ == "__main__":
    main()
