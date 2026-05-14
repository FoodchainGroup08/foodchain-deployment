#!/usr/bin/env python3
"""
seed-menu-images.py
─────────────────────────────────────────────────────────────────────────────
Finds a food photo for every menu_item where image_url is NULL,
downloads it, uploads to S3, and updates the database.

Requirements:
    pip install pymysql boto3 requests python-dotenv

Image sources (at least one API key recommended):
    - Pexels  → https://www.pexels.com/api/  (free, 200 req/hour)
    - Unsplash → https://unsplash.com/developers (free, 50 req/hour)
    - If neither key is provided, falls back to LoremFlickr (no key needed,
      searches Flickr by food name — quality varies).

Usage:
    # Preview only — no DB writes, no S3 uploads:
    python seed-menu-images.py --dry-run

    # Run for real:
    python seed-menu-images.py

    # Only update items in a specific branch (optional):
    python seed-menu-images.py --branch-id 00e03993-6425-4703-a38f-cc661ceedf44
"""

import argparse
import os
import re
import sys
import time
import uuid

import boto3
import pymysql
import requests
from botocore.exceptions import BotoCoreError, ClientError

# ── Config ─────────────────────────────────────────────────────────────────────
# Set these via environment variables or a .env file.
# Example .env is at the bottom of this file.

DB_HOST    = os.getenv("DB_HOST",    "localhost")
DB_PORT    = int(os.getenv("DB_PORT", "3306"))
DB_USER    = os.getenv("DB_USER",    "root")
DB_PASS    = os.getenv("DB_PASS",    "")
DB_NAME    = os.getenv("DB_NAME",    "menu_db")

AWS_KEY    = os.getenv("AWS_ACCESS_KEY_ID")
AWS_SECRET = os.getenv("AWS_SECRET_ACCESS_KEY")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
S3_BUCKET  = os.getenv("AWS_S3_BUCKET_NAME", "foodchain-images-bucket")

PEXELS_KEY   = os.getenv("PEXELS_API_KEY",       "")
UNSPLASH_KEY = os.getenv("UNSPLASH_ACCESS_KEY",  "")

# How long to wait between items to avoid rate limiting
REQUEST_DELAY_SECONDS = 0.6

# ── Image search ───────────────────────────────────────────────────────────────

def search_pexels(query: str) -> str | None:
    """Return a square-ish photo URL from Pexels, or None on failure."""
    if not PEXELS_KEY:
        return None
    try:
        resp = requests.get(
            "https://api.pexels.com/v1/search",
            headers={"Authorization": PEXELS_KEY},
            params={"query": f"{query} food dish", "per_page": 3, "orientation": "square"},
            timeout=10,
        )
        if resp.status_code == 200:
            photos = resp.json().get("photos", [])
            if photos:
                return photos[0]["src"]["large"]
        elif resp.status_code == 429:
            print("    [WARN] Pexels rate limit hit — waiting 60 s...")
            time.sleep(60)
    except Exception as e:
        print(f"    [WARN] Pexels error: {e}")
    return None


def search_unsplash(query: str) -> str | None:
    """Return a photo URL from Unsplash, or None on failure."""
    if not UNSPLASH_KEY:
        return None
    try:
        resp = requests.get(
            "https://api.unsplash.com/search/photos",
            params={
                "query": f"{query} food",
                "per_page": 3,
                "orientation": "squarish",
                "client_id": UNSPLASH_KEY,
            },
            timeout=10,
        )
        if resp.status_code == 200:
            results = resp.json().get("results", [])
            if results:
                return results[0]["urls"]["regular"]
        elif resp.status_code == 403:
            print("    [WARN] Unsplash rate limit or auth error.")
    except Exception as e:
        print(f"    [WARN] Unsplash error: {e}")
    return None


def fallback_loremflickr(query: str) -> str:
    """
    LoremFlickr — searches Flickr by keyword, no API key needed.
    Returns a direct image URL (400×400).
    """
    safe = re.sub(r"[^a-z0-9 ]", "", query.lower()).replace(" ", ",")
    return f"https://loremflickr.com/400/400/{safe},food?lock={abs(hash(query)) % 9999}"


# Curated keyword → Pexels CDN URL map for common African / fast-food items.
# These are fallbacks if both APIs are unconfigured AND LoremFlickr is slow.
KEYWORD_FALLBACKS: dict[str, str] = {
    "jollof":    "https://images.pexels.com/photos/5410400/pexels-photo-5410400.jpeg",
    "rice":      "https://images.pexels.com/photos/4518612/pexels-photo-4518612.jpeg",
    "chicken":   "https://images.pexels.com/photos/2338407/pexels-photo-2338407.jpeg",
    "suya":      "https://images.pexels.com/photos/410648/pexels-photo-410648.jpeg",
    "pepper":    "https://images.pexels.com/photos/1409050/pexels-photo-1409050.jpeg",
    "egusi":     "https://images.pexels.com/photos/5410400/pexels-photo-5410400.jpeg",
    "plantain":  "https://images.pexels.com/photos/5950843/pexels-photo-5950843.jpeg",
    "yam":       "https://images.pexels.com/photos/5950843/pexels-photo-5950843.jpeg",
    "beans":     "https://images.pexels.com/photos/4518612/pexels-photo-4518612.jpeg",
    "shawarma":  "https://images.pexels.com/photos/2955819/pexels-photo-2955819.jpeg",
    "puff":      "https://images.pexels.com/photos/209206/pexels-photo-209206.jpeg",
    "burger":    "https://images.pexels.com/photos/1639557/pexels-photo-1639557.jpeg",
    "pizza":     "https://images.pexels.com/photos/825661/pexels-photo-825661.jpeg",
    "pasta":     "https://images.pexels.com/photos/1279330/pexels-photo-1279330.jpeg",
    "noodle":    "https://images.pexels.com/photos/1279330/pexels-photo-1279330.jpeg",
    "soup":      "https://images.pexels.com/photos/2474661/pexels-photo-2474661.jpeg",
    "stew":      "https://images.pexels.com/photos/2474661/pexels-photo-2474661.jpeg",
    "salad":     "https://images.pexels.com/photos/1059905/pexels-photo-1059905.jpeg",
    "steak":     "https://images.pexels.com/photos/1640777/pexels-photo-1640777.jpeg",
    "beef":      "https://images.pexels.com/photos/323682/pexels-photo-323682.jpeg",
    "fish":      "https://images.pexels.com/photos/3655916/pexels-photo-3655916.jpeg",
    "shrimp":    "https://images.pexels.com/photos/691668/pexels-photo-691668.jpeg",
    "sandwich":  "https://images.pexels.com/photos/1633578/pexels-photo-1633578.jpeg",
    "wrap":      "https://images.pexels.com/photos/2955819/pexels-photo-2955819.jpeg",
    "bread":     "https://images.pexels.com/photos/209206/pexels-photo-209206.jpeg",
    "egg":       "https://images.pexels.com/photos/824635/pexels-photo-824635.jpeg",
    "fries":     "https://images.pexels.com/photos/1583884/pexels-photo-1583884.jpeg",
    "chips":     "https://images.pexels.com/photos/1583884/pexels-photo-1583884.jpeg",
    "wings":     "https://images.pexels.com/photos/2338407/pexels-photo-2338407.jpeg",
    "cake":      "https://images.pexels.com/photos/1126359/pexels-photo-1126359.jpeg",
    "ice cream": "https://images.pexels.com/photos/1352278/pexels-photo-1352278.jpeg",
    "coffee":    "https://images.pexels.com/photos/302899/pexels-photo-302899.jpeg",
    "juice":     "https://images.pexels.com/photos/1337825/pexels-photo-1337825.jpeg",
    "water":     "https://images.pexels.com/photos/327090/pexels-photo-327090.jpeg",
    "smoothie":  "https://images.pexels.com/photos/1337825/pexels-photo-1337825.jpeg",
    "meat":      "https://images.pexels.com/photos/323682/pexels-photo-323682.jpeg",
    "vegetable": "https://images.pexels.com/photos/1059905/pexels-photo-1059905.jpeg",
    "sausage":   "https://images.pexels.com/photos/410648/pexels-photo-410648.jpeg",
}

GENERIC_FALLBACK = "https://images.pexels.com/photos/1640777/pexels-photo-1640777.jpeg"


def keyword_fallback(name: str) -> str:
    name_lower = name.lower()
    for keyword, url in KEYWORD_FALLBACKS.items():
        if keyword in name_lower:
            return url
    return GENERIC_FALLBACK


def find_image_source_url(item_name: str) -> str:
    """
    Priority order:
    1. Pexels API  (best quality, needs free API key)
    2. Unsplash API (great quality, needs free API key)
    3. LoremFlickr (no key, Flickr-backed, reliable)
    4. Keyword map (hardcoded fallback, always works)
    """
    url = search_pexels(item_name)
    if url:
        return url

    url = search_unsplash(item_name)
    if url:
        return url

    # No API keys configured — use LoremFlickr
    if not PEXELS_KEY and not UNSPLASH_KEY:
        return fallback_loremflickr(item_name)

    # APIs configured but returned nothing — keyword map
    return keyword_fallback(item_name)


# ── S3 upload ──────────────────────────────────────────────────────────────────

def build_s3_client():
    kwargs = {"region_name": AWS_REGION}
    if AWS_KEY and AWS_SECRET:
        kwargs["aws_access_key_id"]     = AWS_KEY
        kwargs["aws_secret_access_key"] = AWS_SECRET
    return boto3.client("s3", **kwargs)


def upload_image_to_s3(s3, source_url: str, item_name: str) -> str:
    """Download image from source_url, upload to S3, return the public S3 URL."""
    resp = requests.get(source_url, timeout=20)
    resp.raise_for_status()

    content_type = resp.headers.get("Content-Type", "image/jpeg").split(";")[0].strip()
    ext = "jpg" if "jpeg" in content_type else content_type.split("/")[-1]
    if ext not in ("jpg", "jpeg", "png", "webp", "gif"):
        ext = "jpg"

    safe_name = re.sub(r"[^a-z0-9]+", "_", item_name.lower()).strip("_")
    key = f"menu-items/{uuid.uuid4()}-{safe_name}.{ext}"

    s3.put_object(
        Bucket=S3_BUCKET,
        Key=key,
        Body=resp.content,
        ContentType=content_type,
    )

    return f"https://{S3_BUCKET}.s3.{AWS_REGION}.amazonaws.com/{key}"


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Seed food images for menu items that have no image_url."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would happen without writing to S3 or DB.",
    )
    parser.add_argument(
        "--branch-id",
        default=None,
        help="Only process menu items belonging to this branch UUID.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Process at most N items (useful for testing).",
    )
    args = parser.parse_args()

    # ── Validate config ──────────────────────────────────────────────────────
    missing = []
    if not AWS_KEY:
        missing.append("AWS_ACCESS_KEY_ID")
    if not AWS_SECRET:
        missing.append("AWS_SECRET_ACCESS_KEY")
    if missing and not args.dry_run:
        print(f"[ERROR] Missing required env vars: {', '.join(missing)}")
        print("        Set them or run with --dry-run to preview.")
        sys.exit(1)

    if not PEXELS_KEY and not UNSPLASH_KEY:
        print("[INFO] No PEXELS_API_KEY or UNSPLASH_ACCESS_KEY set.")
        print("       Falling back to LoremFlickr (no key needed, quality varies).")
        print("       For better images, get a free Pexels key at https://www.pexels.com/api/\n")

    # ── Connect to DB ────────────────────────────────────────────────────────
    try:
        conn = pymysql.connect(
            host=DB_HOST, port=DB_PORT,
            user=DB_USER, password=DB_PASS,
            database=DB_NAME, charset="utf8mb4",
            cursorclass=pymysql.cursors.DictCursor,
        )
    except Exception as e:
        print(f"[ERROR] Cannot connect to database: {e}")
        sys.exit(1)

    # ── Connect to S3 ────────────────────────────────────────────────────────
    s3 = None
    if not args.dry_run:
        try:
            s3 = build_s3_client()
            s3.head_bucket(Bucket=S3_BUCKET)
        except (BotoCoreError, ClientError) as e:
            print(f"[ERROR] Cannot reach S3 bucket '{S3_BUCKET}': {e}")
            sys.exit(1)

    # ── Fetch items ──────────────────────────────────────────────────────────
    with conn:
        with conn.cursor() as cursor:
            if args.branch_id:
                # menu_items → menu_categories → branches (category has branch_id)
                cursor.execute(
                    """
                    SELECT mi.id, mi.name
                    FROM menu_items mi
                    JOIN menu_categories mc ON mi.category_id = mc.id
                    WHERE (mi.image_url IS NULL OR mi.image_url = '')
                      AND mc.branch_id = %s
                    ORDER BY mi.name
                    """,
                    (args.branch_id,),
                )
            else:
                cursor.execute(
                    """
                    SELECT id, name
                    FROM menu_items
                    WHERE image_url IS NULL OR image_url = ''
                    ORDER BY name
                    """
                )
            items = cursor.fetchall()

        if args.limit:
            items = items[: args.limit]

        total = len(items)
        print(f"Found {total} menu item(s) with no image.\n")
        if not items:
            return

        updated = 0
        failed  = 0

        for i, item in enumerate(items, 1):
            item_id   = item["id"]
            item_name = item["name"]
            print(f"[{i}/{total}] {item_name} ({item_id[:8]}…)", end=" → ", flush=True)

            try:
                source_url = find_image_source_url(item_name)

                if args.dry_run:
                    print(f"[DRY RUN] {source_url}")
                    continue

                s3_url = upload_image_to_s3(s3, source_url, item_name)

                with conn.cursor() as cursor:
                    cursor.execute(
                        "UPDATE menu_items SET image_url = %s, updated_at = NOW() WHERE id = %s",
                        (s3_url, item_id),
                    )
                conn.commit()

                print(f"OK  {s3_url}")
                updated += 1

            except KeyboardInterrupt:
                print("\n[INTERRUPTED] Stopping early.")
                break
            except Exception as e:
                print(f"FAILED — {e}")
                failed += 1

            time.sleep(REQUEST_DELAY_SECONDS)

        print(f"\n{'─'*60}")
        if args.dry_run:
            print(f"DRY RUN complete — {total} item(s) would be processed.")
        else:
            print(f"Done.  Updated: {updated}   Failed: {failed}   Total: {total}")


if __name__ == "__main__":
    main()


# ─────────────────────────────────────────────────────────────────────────────
# .env.example  (copy to .env and fill in your values)
# ─────────────────────────────────────────────────────────────────────────────
#
# # Database (same values as your docker-compose)
# DB_HOST=localhost
# DB_PORT=3306
# DB_USER=root
# DB_PASS=your_mysql_password
# DB_NAME=menu_db
#
# # AWS  (same as your deployment .env)
# AWS_ACCESS_KEY_ID=AKIA...
# AWS_SECRET_ACCESS_KEY=...
# AWS_REGION=us-east-1
# AWS_S3_BUCKET_NAME=foodchain-images-bucket
#
# # Image API (get a free key at https://www.pexels.com/api/)
# PEXELS_API_KEY=your_pexels_key_here
#
# # Unsplash (optional backup — https://unsplash.com/developers)
# UNSPLASH_ACCESS_KEY=your_unsplash_key_here
