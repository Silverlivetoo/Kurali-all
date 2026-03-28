#!/usr/bin/env python3
"""
Tavily Search Tool - Refactored Version
Enhanced with caching, retry mechanisms, and improved error handling.
"""

import argparse
import json
import os
import pathlib
import re
import sys
import urllib.request
import hashlib
import pickle
import logging
import time
from typing import Dict, List, Optional, Union

TAVILY_URL = "https://api.tavily.com/search"

# 设置日志配置
logging.basicConfig(
    level=logging.WARNING,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/tmp/tavily_search.log', mode='a'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("tavily_search")


def load_api_key() -> Optional[str]:
    """
    Load Tavily API key from environment variable or config file.
    
    Returns:
        API key string if found, None otherwise
        
    Raises:
        SystemExit if config file has insecure permissions
    """
    # 1. Check environment variable
    key = os.environ.get("TAVILY_API_KEY")
    if key:
        logger.debug("API key loaded from environment variable")
        return key.strip()
    
    # 2. Check config file
    env_path = pathlib.Path.home() / ".openclaw" / ".env"
    
    # Security check: verify config file permissions
    if env_path.exists():
        try:
            stat_info = env_path.stat()
            if stat_info.st_mode & 0o077 != 0:
                logger.warning(f"Config file has insecure permissions: {env_path}")
                raise SystemExit(f"Config file {env_path} has insecure permissions")
        except Exception as e:
            logger.error(f"Failed to check file permissions: {e}")
    
        # Read config file
        try:
            txt = env_path.read_text(encoding="utf-8", errors="ignore")
            m = re.search(r'^\s*TAVILY_API_KEY\s*=\s*(.+?)\s*$', txt, re.M)
            if m:
                v = m.group(1).strip().strip('"').strip("'")
                if v:
                    logger.debug("API key loaded from config file")
                    return v
        except Exception as e:
            logger.error(f"Failed to read config file: {e}")
            return None
    
    logger.error("TAVILY_API_KEY not found in environment or config file")
    return None


def validate_api_key(key: str) -> bool:
    """
    Validate API key format.
    
    Args:
        key: API key string
        
    Returns:
        True if key appears valid, False otherwise
    """
    if not key:
        logger.error("API key is empty")
        return False
    
    # Basic validation: check length and format
    if len(key) < 10:
        logger.error("API key appears too short")
        return False
    
    # Check if it contains only alphanumeric characters
    if not re.match(r'^[a-zA-Z0-9_\-]+$', key):
        logger.error("API key contains invalid characters")
        return False
    
    logger.debug("API key validation passed")
    return True


def create_cache_path(query: str, cache_dir: Optional[str]) -> Optional[pathlib.Path]:
    """
    Create cache path for query with hash.
    
    Args:
        query: Search query string
        cache_dir: Cache directory path
        
    Returns:
        Cache file path if cache enabled, None otherwise
    """
    if not cache_dir:
        logger.debug("Cache disabled")
        return None
    
    cache_path = pathlib.Path(cache_dir)
    
    # Check cache directory permissions
    try:
        cache_path.mkdir(parents=True, exist_ok=True)
        stat_info = cache_path.stat()
        if stat_info.st_mode & 0o077 != 0:
            logger.warning(f"Cache directory has insecure permissions: {cache_path}")
            return None
    except Exception as e:
        logger.error(f"Failed to create cache directory: {e}")
        return None
    
    # Generate hash using SHA256 for better collision resistance
    query_hash = hashlib.sha256(query.encode()).hexdigest()
    cache_file = cache_path / f"{query_hash}.cache"
    
    return cache_file


def get_cache_expiry_time(query: str) -> int:
    """
    Determine cache expiry time based on query type.
    
    Args:
        query: Search query string
        
    Returns:
        Cache expiry time in seconds
    """
    # Dynamic expiry based on query type
    if query.lower().startswith("weather"):
        return 300  # Weather queries: 5 minutes
    elif query.lower().startswith("stock"):
        return 300  # Stock queries: 5 minutes
    elif query.lower().startswith("news"):
        return 1800  # News queries: 30 minutes
    elif query.lower().startswith("history"):
        return 86400  # Historical queries: 24 hours
    else:
        return 3600  # General queries: 1 hour


def load_cache(cache_file: pathlib.Path) -> Optional[Dict]:
    """
    Load cached search result.
    
    Args:
        cache_file: Cache file path
        
    Returns:
        Cached result if valid, None otherwise
    """
    if not cache_file.exists():
        logger.debug(f"No cache found for {cache_file}")
        return None
    
    try:
        with open(cache_file, "rb") as f:
            cache_data = pickle.load(f)
        
        # Check expiry time
        expiry = get_cache_expiry_time(cache_data.get("query", ""))
        timestamp = cache_data.get("timestamp", 0)
        
        if time.time() - timestamp < expiry:
            logger.info(f"Using cached result for query: {cache_data.get('query')}")
            return cache_data["result"]
        else:
            logger.info(f"Cache expired for query: {cache_data.get('query')}")
            return None
            
    except Exception as e:
        logger.warning(f"Failed to load cache: {e}")
        return None


def save_cache(cache_file: pathlib.Path, query: str, result: Dict) -> bool:
    """
    Save search result to cache.
    
    Args:
        cache_file: Cache file path
        query: Search query string
        result: Search result
        
    Returns:
        True if cache saved successfully, False otherwise
    """
    try:
        cache_data = {
            "timestamp": time.time(),
            "query": query,
            "result": result
        }
        
        with open(cache_file, "wb") as f:
            pickle.dump(cache_data, f)
        
        logger.info(f"Cached result for query: {query}")
        return True
        
    except Exception as e:
        logger.warning(f"Failed to save cache: {e}")
        return False


def make_tavily_request(query: str, api_key: str, max_results: int, 
                        include_answer: bool, search_depth: str) -> Dict:
    """
    Make request to Tavily API with retry mechanism.
    
    Args:
        query: Search query string
        api_key: Tavily API key
        max_results: Maximum number of results
        include_answer: Whether to include answer
        search_depth: Search depth
        
    Returns:
        Search result dictionary
        
    Raises:
        SystemExit if request fails after retries
    """
    # Prepare payload
    payload = {
        "api_key": api_key,
        "query": query,
        "max_results": max_results,
        "search_depth": search_depth,
        "include_answer": bool(include_answer),
        "include_images": False,
        "include_raw_content": False,
    }
    
    data = json.dumps(payload).encode("utf-8")
    
    # Retry mechanism
    max_attempts = 3
    for attempt in range(max_attempts):
        try:
            logger.debug(f"Attempt {attempt + 1}/{max_attempts} for query: {query}")
            
            req = urllib.request.Request(
                TAVILY_URL,
                data=data,
                headers={
                    "Content-Type": "application/json",
                    "Accept": "application/json"
                },
                method="POST",
            )
            
            with urllib.request.urlopen(req, timeout=30) as resp:
                body = resp.read().decode("utf-8", errors="replace")
            
            # Parse response
            try:
                obj = json.loads(body)
            except json.JSONDecodeError as e:
                logger.error(f"API returned non-JSON response: {body[:300]}")
                if attempt < max_attempts - 1:
                    logger.debug(f"Retrying after JSON decode error")
                    time.sleep(1)
                    continue
                else:
                    raise SystemExit(f"Tavily returned non-JSON: {body[:300]}")
            
            # Build output structure
            out = {
                "query": query,
                "answer": obj.get("answer"),
                "results": [],
            }
            
            for r in (obj.get("results") or [])[:max_results]:
                out["results"].append(
                    {
                        "title": r.get("title"),
                        "url": r.get("url"),
                        "content": r.get("content"),
                    }
                )
            
            if not include_answer:
                out.pop("answer", None)
            
            logger.info(f"Search successful: {query}")
            return out
            
        except urllib.error.HTTPError as e:
            logger.warning(f"HTTP error (attempt {attempt + 1}/{max_attempts}): {e}")
            if attempt < max_attempts - 1:
                time.sleep(1)
                continue
            else:
                logger.error(f"Request failed after {max_attempts} attempts")
                raise SystemExit(f"HTTP error {e.code}: {e.reason}")
                
        except urllib.error.URLError as e:
            logger.warning(f"URL error (attempt {attempt + 1}/{max_attempts}): {e}")
            if attempt < max_attempts - 1:
                time.sleep(2)  # Longer wait for network errors
                continue
            else:
                logger.error(f"Network error after {max_attempts} attempts")
                raise SystemExit(f"Failed to connect to Tavily: {e}")
                
        except Exception as e:
            logger.error(f"Unexpected error: {e}")
            if attempt < max_attempts - 1:
                time.sleep(1)
                continue
            else:
                raise SystemExit(f"Search failed: {e}")


def tavily_search_with_cache(query: str, max_results: int, include_answer: bool, 
                           search_depth: str, cache_dir: Optional[str] = None) -> Dict:
    """
    Search Tavily with caching support.
    
    Args:
        query: Search query string
        max_results: Maximum number of results (1-10)
        include_answer: Whether to include answer
        search_depth: Search depth ('basic' or 'advanced')
        cache_dir: Cache directory path
        
    Returns:
        Search result dictionary
        
    Raises:
        SystemExit if API key not found or request fails
    """
    # Load API key
    api_key = load_api_key()
    if not api_key:
        raise SystemExit(
            "Missing TAVILY_API_KEY. Set env var TAVILY_API_KEY or add it to ~/.openclaw/.env"
        )
    
    # Validate API key
    if not validate_api_key(api_key):
        raise SystemExit("Invalid API key format")
    
    # Check cache if enabled
    cache_enabled = cache_dir is not None
    cache_file = None
    
    if cache_enabled:
        cache_file = create_cache_path(query, cache_dir)
        if cache_file:
            cached_result = load_cache(cache_file)
            if cached_result:
                return cached_result
    
    # Make request
    result = make_tavily_request(query, api_key, max_results, include_answer, search_depth)
    
    # Save cache if enabled
    if cache_enabled and cache_file:
        save_cache(cache_file,  query, result)
    
    return result


def format_to_brave_like(obj: Dict) -> Dict:
    """
    Convert Tavily result to Brave-like format.
    
    Args:
        obj: Tavily search result
        
    Returns:
        Brave-like formatted result
    """
    results = []
    for r in obj.get("results", []) or []:
        results.append(
            {
                "title": r.get("title"),
                "url": r.get("url"),
                "snippet": r.get("content"),
            }
        )
    out = {"query": obj.get("query"), "results": results}
    if "answer" in obj:
        out["answer"] = obj.get("answer")
    return out


def format_to_markdown(obj: Dict) -> str:
    """
    Convert Tavily result to Markdown format.
    
    Args:
        obj: Tavily search result
        
    Returns:
        Markdown formatted string
    """
    lines = []
    
    if obj.get("answer"):
        lines.append(obj["answer"].strip())
        lines.append("")
    
    for i, r in enumerate(obj.get("results", []) or [], 1):
        title = (r.get("title") or "").strip() or r.get("url") or "(no title)"
        url = r.get("url") or ""
        snippet = (r.get("content") or "").strip()
        
        lines.append(f"{i}. {title}")
        if url:
            lines.append(f"   {url}")
        if snippet:
            lines.append(f"   - {snippet}")
    
    return "\n".join(lines).strip() + "\n"


def format_to_html(obj: Dict) -> str:
    """
    Convert Tavily result to HTML format.
    
    Args:
        obj: Tavily search result
        
    Returns:
        HTML formatted string
    """
    html = []
    
    if obj.get("answer"):
        html.append(f"<p><strong>Answer:</strong> {obj['answer']}</p>")
    
    html.append("<ol>")
    for r in obj.get("results", []) or []:
        title = (r.get("title") or "").strip() or r.get("url") or "(no title)"
        url = r.get("url") or ""
        snippet = (r.get("content") or "").strip()
        
        html.append("<li>")
        html.append(f"<h3>{title}</h3>")
        if url:
            html.append(f"<a href='{url}'>{url}</a>")
        if snippet:
            html.append(f"<p>{snippet}</p>")
        html.append("</li>")
    html.append("</ol>")
    
    return "\n".join(html)


def format_output(obj: Dict, format_type: str) -> str:
    """
    Format result according to specified output format.
    
    Args:
        obj: Tavily search result
        format_type: Output format
        
    Returns:
        Formatted output string
    """
    if format_type == "md":
        return format_to_markdown(obj)
    elif format_type == "html":
        return format_to_html(obj)
    elif format_type == "brave":
        obj = format_to_brave_like(obj)
        return json.dumps(obj, ensure_ascii=False)
    else:
        return json.dumps(obj, ensure_ascii=False)


def main():
    """
    Main entry point for Tavily search tool.
    
    Handles command line arguments and executes search.
    """
    ap = argparse.ArgumentParser(
        description="Tavily Search Tool with caching and retry mechanisms"
    )
    
    # Required arguments
    ap.add_argument("--query", required=True, help="Search query")
    
    # Optional arguments
    ap.add_argument("--max-results", type=int, default=5,
                    help="Maximum number of results (1-10)")
    ap.add_argument("--include-answer", action="store_true",
                    help="Include answer in results")
    ap.add_argument("--search-depth", default="basic",
                    choices=["basic", "advanced"], help="Tavily search depth")
    ap.add_argument("--cache-dir", help="Cache directory path")
    ap.add_argument("--no-cache", action="store_true",
                    help="Disable caching")
    ap.add_argument("--format", default="raw",
                    choices=["raw", "brave", "md", "html"],
                    help="Output format: raw | brave | md | html")
    ap.add_argument("--verbose", action="store_true",
                    help="Enable verbose logging")
    
    args = ap.parse_args()
    
    # Configure logging
    if args.verbose:
        logger.setLevel(logging.DEBUG)
        logger.debug(f"Arguments: {args}")
    
    # Validate max results
    if args.max_results < 1 or args.max_results > 10:
        logger.warning(f"max_results out of range: {args.max_results}")
        args.max_results = max(1, min(args.max_results, 10))
    
    # Execute search
    cache_dir = args.cache_dir if not args.no_cache else None
    
    try:
        result = tavily_search_with_cache(
            query=args.query,
            max_results=args.max_results,
            include_answer=args.include_answer,
            search_depth=args.search_depth,
            cache_dir=cache_dir
        )
        
        # Format output
        output = format_output(result, args.format)
        sys.stdout.write(output)
        
    except SystemExit as e:
        logger.error(f"System exit: {e}")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()