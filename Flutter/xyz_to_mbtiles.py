#!/usr/bin/env python3
import os, sys, sqlite3, argparse, time

def xyz_to_mbtiles(src, dst, fmt):
    if not os.path.isdir(src):
        raise SystemExit(f"Source folder not found: {src}")

    # Prepare DB
    if os.path.exists(dst):
        os.remove(dst)
    db = sqlite3.connect(dst)
    cur = db.cursor()
    cur.executescript("""
    PRAGMA journal_mode=OFF;
    PRAGMA synchronous=OFF;
    CREATE TABLE metadata (name TEXT, value TEXT);
    CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB);
    CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row);
    """)
    db.commit()

    # Walk z/x/y
    z_min, z_max = 99, -1
    count = 0
    for z_name in sorted(os.listdir(src), key=lambda s: int(s) if s.isdigit() else 999):
        if not z_name.isdigit(): 
            continue
        z = int(z_name)
        z_min = min(z_min, z); z_max = max(z_max, z)
        z_dir = os.path.join(src, z_name)
        if not os.path.isdir(z_dir): 
            continue
        for x_name in os.listdir(z_dir):
            x_dir = os.path.join(z_dir, x_name)
            if not x_name.isdigit() or not os.path.isdir(x_dir):
                continue
            x = int(x_name)
            for y_file in os.listdir(x_dir):
                if not (y_file.endswith(".png") or y_file.endswith(".jpg") or y_file.endswith(".jpeg")):
                    continue
                y_name = os.path.splitext(y_file)[0]
                if not y_name.isdigit():
                    continue
                y_xyz = int(y_name)
                # XYZ -> TMS flip
                y_tms = (1 << z) - 1 - y_xyz
                with open(os.path.join(x_dir, y_file), "rb") as f:
                    blob = f.read()
                cur.execute("INSERT OR REPLACE INTO tiles VALUES (?,?,?,?)",
                            (z, x, y_tms, sqlite3.Binary(blob)))
                count += 1
                if count % 5000 == 0:
                    db.commit()
                    print(f"Inserted {count} tiles…")

    # Metadata
    cur.executemany("INSERT INTO metadata(name,value) VALUES(?,?)", [
        ("name", os.path.basename(dst)),
        ("type", "baselayer"),
        ("version", "1.0"),
        ("description", "Packed from XYZ folder"),
        ("format", fmt.lower()),
        ("minzoom", str(z_min if z_min != 99 else 0)),
        ("maxzoom", str(z_max if z_max != -1 else 0)),
        ("attribution", ""),
    ])
    db.commit()
    db.close()
    print(f"Done. Wrote {count} tiles to {dst} (z {z_min}..{z_max})")

if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Pack XYZ tiles into MBTiles (raster).")
    ap.add_argument("src", help="Path to XYZ root (contains z folders like 4,5,6,...)")
    ap.add_argument("dst", help="Output .mbtiles path")
    ap.add_argument("--format", default="png", choices=["png","jpg","jpeg"], help="Tile image format")
    args = ap.parse_args()
    xyz_to_mbtiles(args.src, args.dst, args.format)