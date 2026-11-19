#!/usr/bin/env python3
"""
Yandex Music API Track Resolver
Resolves track IDs to proper track metadata using Yandex Music API

Usage:
    python yandex_music_api_resolver.py --token YOUR_TOKEN --track-id 464769
    python yandex_music_api_resolver.py --token YOUR_TOKEN --playlist-id 1211119227

API Usage:
    1. Get a Yandex Music token from developer account or via OAuth
    2. Use the token to query track information
"""

import argparse
import json
import requests
import base64
import struct
import os
import sys
from pathlib import Path

class YandexMusicAPI:
    BASE_URL = "https://api.music.yandex.net"
    
    def __init__(self, token):
        self.token = token
        self.headers = {
            "Authorization": f"YandexToken {token}",
            "Content-Type": "application/json"
        }
    
    def get_track(self, track_id):
        """Get track information by track ID"""
        url = f"{self.BASE_URL}/v1/tracks/{track_id}"
        try:
            response = requests.get(url, headers=self.headers)
            if response.status_code == 200:
                return response.json()
        except Exception as e:
            print(f"Error fetching track: {e}", file=sys.stderr)
        return None
    
    def get_track_by_rid(self, rid):
        """Get track by RID (regional ID)"""
        url = f"{self.BASE_URL}/v1/tracks"
        params = {"rid": rid}
        try:
            response = requests.get(url, headers=self.headers, params=params)
            if response.status_code == 200:
                return response.json()
        except Exception as e:
            print(f"Error fetching track by RID: {e}", file=sys.stderr)
        return None
    
    def get_playlist_tracks(self, playlist_id):
        """Get tracks from a playlist"""
        url = f"{self.BASE_URL}/v1/playlists/{playlist_id}/tracks"
        try:
            response = requests.get(url, headers=self.headers)
            if response.status_code == 200:
                return response.json()
        except Exception as e:
            print(f"Error fetching playlist tracks: {e}", file=sys.stderr)
        return None
    
    def search(self, query, type="track", count=10):
        """Search for tracks, artists, albums, or playlists"""
        url = f"{self.BASE_URL}/v1/search"
        params = {
            "text": query,
            "type": type,
            "count": count
        }
        try:
            response = requests.get(url, headers=self.headers, params=params)
            if response.status_code == 200:
                return response.json()
        except Exception as e:
            print(f"Error searching: {e}", file=sys.stderr)
        return None


def extract_protobuf_info(data):
    """
    Extract track information from protobuf-encoded data
    This is used for LevelDB SST files
    """
    # Simplified protobuf parser for Yandex Music track data
    # In production, use a proper protobuf library
    
    info = {}
    
    # Try to find strings in the data that look like track info
    # This is a heuristic approach
    text = data.decode('utf-8', errors='ignore') if isinstance(data, bytes) else data
    
    # Look for common patterns
    import re
    
    # Track titles often appear near duration patterns
    duration_match = re.search(r'"duration"\s*:\s*(\d+)', text)
    if duration_match:
        info['duration'] = int(duration_match.group(1))
    
    # Artist names
    artist_match = re.search(r'"artist"\s*:\s*"([^"]+)"', text)
    if artist_match:
        info['artist'] = artist_match.group(1)
    
    # Album names
    album_match = re.search(r'"album"\s*:\s*"([^"]+)"', text)
    if album_match:
        info['album'] = album_match.group(1)
    
    # Title
    title_match = re.search(r'"title"\s*:\s*"([^"]+)"', text)
    if title_match:
        info['title'] = title_match.group(1)
    
    return info


def decode_leveldb_track(filepath):
    """
    Decode track information from LevelDB SST file
    """
    try:
        with open(filepath, 'rb') as f:
            data = f.read()
        
        info = extract_protobuf_info(data)
        
        # Try to find track ID
        track_id_match = re.search(r'"trackId"\s*:\s*(\d+)', data.decode('utf-8', errors='ignore'))
        if track_id_match:
            info['trackId'] = int(track_id_match.group(1))
        
        return info
    except Exception as e:
        print(f"Error decoding LevelDB file: {e}", file=sys.stderr)
    return {}


def main():
    parser = argparse.ArgumentParser(description="Yandex Music API Track Resolver")
    parser.add_argument("--token", required=True, help="Yandex Music API token")
    parser.add_argument("--track-id", type=int, help="Track ID to resolve")
    parser.add_argument("--rid", help="RID (regional ID) to resolve")
    parser.add_argument("--playlist-id", type=int, help="Playlist ID to get tracks from")
    parser.add_argument("--leveldb-path", help="Path to LevelDB SST file to parse")
    
    args = parser.parse_args()
    
    api = YandexMusicAPI(args.token)
    
    if args.track_id:
        track = api.get_track(args.track_id)
        if track:
            print(json.dumps(track, indent=2))
            if 'track' in track:
                print(f"\nTitle: {track['track'].get('title')}")
                print(f"Artist: {track['track'].get('artists', [{}])[0].get('name')}")
                print(f"Album: {track['track'].get('albums', [{}])[0].get('title')}")
        else:
            print(f"Could not resolve track ID {args.track_id}")
    
    elif args.rid:
        track = api.get_track_by_rid(args.rid)
        if track:
            print(json.dumps(track, indent=2))
        else:
            print(f"Could not resolve RID {args.rid}")
    
    elif args.playlist_id:
        playlist = api.get_playlist_tracks(args.playlist_id)
        if playlist:
            print(json.dumps(playlist, indent=2))
        else:
            print(f"Could not get tracks from playlist {args.playlist_id}")
    
    elif args.leveldb_path:
        info = decode_leveldb_track(args.leveldb_path)
        print(json.dumps(info, indent=2))
    
    else:
        parser.print_help()


if __name__ == "__main__":
    main()