#!/usr/bin/env python3
"""
Simple MBTiles tile server for web development
Extracts tiles from MBTiles file and serves them via HTTP
"""

import sqlite3
import os
import http.server
import socketserver
import urllib.parse
import json
from pathlib import Path

class MBTilesHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, mbtiles_path=None, **kwargs):
        self.mbtiles_path = mbtiles_path
        super().__init__(*args, **kwargs)
    
    def do_GET(self):
        # Parse the URL
        parsed_path = urllib.parse.urlparse(self.path)
        path_parts = parsed_path.path.strip('/').split('/')
        
        # Handle tile requests: /{z}/{x}/{y}.png
        if len(path_parts) == 3 and path_parts[2].endswith(('.png', '.jpg', '.jpeg')):
            try:
                z = int(path_parts[0])
                x = int(path_parts[1])
                y = int(path_parts[2].split('.')[0])  # Remove extension
                
                tile_data = self.get_tile(z, x, y)
                if tile_data:
                    self.send_response(200)
                    self.send_header('Content-Type', 'image/png')
                    self.send_header('Access-Control-Allow-Origin', '*')
                    self.send_header('Access-Control-Allow-Methods', 'GET')
                    self.send_header('Access-Control-Allow-Headers', 'Content-Type')
                    self.end_headers()
                    self.wfile.write(tile_data)
                    return
                else:
                    self.send_error(404, "Tile not found")
                    return
            except ValueError:
                self.send_error(400, "Invalid tile coordinates")
                return
        
        # Handle metadata requests
        elif self.path == '/metadata':
            metadata = self.get_metadata()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(json.dumps(metadata).encode('utf-8'))
            return
        
        # Default handling
        super().do_GET()
    
    def get_tile(self, z, x, y):
        """Get tile data from MBTiles database"""
        try:
            conn = sqlite3.connect(self.mbtiles_path)
            cursor = conn.cursor()
            
            # MBTiles uses TMS (Tile Map Service) coordinate system
            # Convert from XYZ to TMS
            tms_y = (1 << z) - 1 - y
            
            cursor.execute(
                "SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=?",
                (z, x, tms_y)
            )
            
            result = cursor.fetchone()
            conn.close()
            
            if result:
                return result[0]
            return None
        except Exception as e:
            print(f"Error getting tile {z}/{x}/{y}: {e}")
            return None
    
    def get_metadata(self):
        """Get metadata from MBTiles database"""
        try:
            conn = sqlite3.connect(self.mbtiles_path)
            cursor = conn.cursor()
            
            cursor.execute("SELECT name, value FROM metadata")
            metadata = dict(cursor.fetchall())
            conn.close()
            
            return metadata
        except Exception as e:
            print(f"Error getting metadata: {e}")
            return {}

def main():
    # Path to MBTiles file
    mbtiles_file = Path(__file__).parent / "web" / "denmark_vfr.mbtiles"
    
    if not mbtiles_file.exists():
        print(f"Error: MBTiles file not found at {mbtiles_file}")
        return
    
    # Create handler with MBTiles file
    def handler(*args, **kwargs):
        return MBTilesHandler(*args, mbtiles_path=str(mbtiles_file), **kwargs)
    
    # Start server
    PORT = 8081
    print(f"Starting MBTiles server on port {PORT}")
    print(f"MBTiles file: {mbtiles_file}")
    print(f"Tile URL template: http://localhost:{PORT}/{{z}}/{{x}}/{{y}}.png")
    print(f"Metadata URL: http://localhost:{PORT}/metadata")
    
    with socketserver.TCPServer(("", PORT), handler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down server...")

if __name__ == "__main__":
    main()