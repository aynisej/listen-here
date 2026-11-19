#!/usr/bin/env python3
"""
LevelDB Parser for Yandex Music Track Metadata
Parses Yandex Music's LevelDB SST files to extract track information

Usage:
    python parse_leveldb.py --db-path /Users/aqshel/Library/Application\ Support/YandexMusic/IndexedB/
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path

def find_sst_files(db_path):
    """Find all SST files in the LevelDB directory"""
    sst_files = []
    for root, dirs, files in os.walk(db_path):
        for f in files:
            if f.endswith('.sst'):
                sst_files.append(os.path.join(root, f))
    return sst_files

def parse_sst_file(filepath):
    """
    Parse an SST file and extract track information
    SST files are protobuf-encoded, so we look for JSON-like content
    """
    try:
        with open(filepath, 'rb') as f:
            data = f.read()
        
        tracks = []
        
        # Try to decode as UTF-8 and look for JSON structures
        try:
            text = data.decode('utf-8', errors='ignore')
            
            # Find track IDs (usually numbers like 464769)
            track_ids = re.findall(r'"trackId"\s*:\s*(\d+)', text)
            track_ids += re.findall(r'(\d{6,})', text)  # 6+ digit numbers
            
            # Find titles
            titles = re.findall(r'"title"\s*:\s*"([^"]+)"', text)
            
            # Find artists
            artists = re.findall(r'"artist"\s*:\s*"([^"]+)"', text)
            if not artists:
                artists = re.findall(r'"name"\s*:\s*"([^"]+)"', text)
            
            # Find albums
            albums = re.findall(r'"album"\s*:\s*"([^"]+)"', text)
            
            # Find durations
            durations = re.findall(r'"duration"\s*:\s*(\d+)', text)
            
            # Compile into track info
            for i, tid in enumerate(set(track_ids)):
                track_info = {
                    'trackId': int(tid) if tid.isdigit() else tid,
                }
                if i < len(titles):
                    track_info['title'] = titles[i]
                if i < len(artists):
                    track_info['artist'] = artists[i]
                if i < len(albums):
                    track_info['album'] = albums[i]
                if i < len(durations):
                    track_info['duration'] = int(durations[i])
                
                tracks.append(track_info)
        
        except UnicodeDecodeError:
            # Binary data, look for embedded strings
            pass
        
        return tracks
    
    except Exception as e:
        print(f"Error parsing {filepath}: {e}", file=sys.stderr)
        return []

def parse_leveldb_indexedb(db_path):
    """
    Parse IndexedDB LevelDB files specifically
    """
    all_tracks = {}
    
    # Check IndexedDB directory
    indexed_db_path = os.path.join(db_path, 'IndexedDB')
    if os.path.exists(indexed_db_path):
        sst_files = find_sst_files(indexed_db_path)
        for sst_file in sst_files:
            tracks = parse_sst_file(sst_file)
            for track in tracks:
                if 'trackId' in track:
                    all_tracks[str(track['trackId'])] = track
    
    # Check for indexed B directory
    indexed_b_path = os.path.join(db_path, 'IndexedB')
    if os.path.exists(indexed_b_path):
        sst_files = find_sst_files(indexed_b_path)
        for sst_file in sst_files:
            tracks = parse_sst_file(sst_file)
            for track in tracks:
                if 'trackId' in track:
                    all_tracks[str(track['trackId'])] = track
    
    # Also check Cache directory
    cache_path = os.path.join(db_path, 'Cache')
    if os.path.exists(cache_path):
        cache_files = [f for f in os.listdir(cache_path) if not f.startswith('.') and not os.path.isdir(os.path.join(cache_path, f))]
        for cache_file in cache_files:
            filepath = os.path.join(cache_path, cache_file)
            try:
                with open(filepath, 'rb') as f:
                    data = f.read()
                text = data.decode('utf-8', errors='ignore')
                
                # Look for track IDs
                track_ids = re.findall(r'"(\d{6,})"', text)
                titles = re.findall(r'"([^"]{3,50})"', text)  # Suspiciously sized strings
                
                for i, tid in enumerate(track_ids):
                    if i + 1 < len(titles):
                        all_tracks[str(tid)] = {
                            'trackId': int(tid),
                            'title': titles[i + 1],
                            'artist': titles[i] if i > 0 else 'Unknown Artist',
                            'album': '',
                            'duration': 0
                        }
            except:
                pass
    
    return all_tracks

def get_current_track_from_db(db_path):
    """
    Extract the currently playing track from LevelDB
    This looks for the most recently accessed/updated track
    """
    indexed_b_path = os.path.join(db_path, 'IndexedB')
    if os.path.exists(indexed_b_path):
        sst_files = find_sst_files(indexed_b_path)
        if sst_files:
            # Get the most recently modified SST file
            latest_file = max(sst_files, key=os.path.getmtime)
            tracks = parse_sst_file(latest_file)
            if tracks:
                return tracks[-1]  # Return last (most recent) track
    return None

def main():
    parser = argparse.ArgumentParser(description="Parse Yandex Music LevelDB for track metadata")
    parser.add_argument("--db-path", required=True, help="Path to Yandex Music LevelDB")
    parser.add_argument("--output", help="Output JSON file for track cache")
    parser.add_argument("--current-only", action="store_true", help="Only output currently playing track")
    
    args = parser.parse_args()
    
    if args.current_only:
        track = get_current_track_from_db(args.db_path)
        if track:
            print(json.dumps(track, indent=2))
        else:
            print("No current track found")
    else:
        tracks = parse_leveldb_indexedb(args.db_path)
        
        if args.output:
            with open(args.output, 'w') as f:
                json.dump({'tracks': tracks}, f, indent=2)
            print(f"Wrote {len(tracks)} tracks to {args.output}")
        else:
            print(json.dumps({'tracks': tracks}, indent=2))


if __name__ == "__main__":
    main()