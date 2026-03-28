#!/usr/bin/env python3
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
from typing import Dict, List, Optional

TAVILY_URL = "https://api.tavily.com/search"


# 设置日志
logging.basicConfig(
    level=logging.WARNING,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("tavily_search")


def load_key() -> Optional[str]:
    """加载 API 密钥，支持环境变量和配置文件"""
    # 首先检查环境变量
    key = os.environ.get("TAVILY_API_KEY")
    if key:
        logger.info("API key loaded from environment variable")
        return key.strip()

    # 检查配置文件
    env_path = pathlib.Path.home() / ".openclaw" / ".env"
    if env_path.exists():
        try:
            txt = env_path.read_text(encoding="utf-8", errors="ignore")
            m = re.search(r'^\s*TAVILY_API_KEY\s*=\s*(.+?)\s*$', txt, re.M)
            if m:
                v = m.group(1).strip().strip('"').strip("'")
                if v:
                    logger.info("API key loaded from config file")
                    return v
        except Exception as e:
            logger.warning(f"Failed to read config file: {e}")
            return None

    logger.error("TAVILY_API_KEY not found in environment or config file")
    return None


def check_file_permissions() -> bool:
    """检查配置文件权限"""
    env_path = pathlib.Path.home() / ".openclaw" / ".env"
    if env_path.exists():
        try:
            stat_info = env_path.stat()
            if stat_info.st_mode & 0o077 != 0:
                logger.warning(f"Config file has insecure permissions: {env_path}")
                return False
            return True
        except Exception as e:
            logger.error(f"Failed to check file permissions: {e}")
            return False
    return True


def tavily_search_with_cache(query: str, max_results: int, include_answer: bool, 
                           search_depth: str, cache_dir: Optional[str] = None) -> Dict:
    """带缓存的 Tavily 搜索"""
    # 检查缓存配置
    cache_enabled = cache_dir is not None
    
    if cache_enabled:
        cache_path = pathlib.Path(cache_dir)
        cache_path.mkdir(parents=True, exist_ok=True)
        
        # 生成查询哈希
        query_hash = hashlib.md5(query.encode()).hexdigest()
        cache_file = cache_path / f"{query_hash}.cache"
        
        # 检查缓存是否存在且未过期（1小时有效期）
        if cache_file.exists():
            try:
                with open(cache_file, "rb") as f:
                    cache_data = pickle.load(f)
                    # 检查缓存时间
                    if cache_data.get("timestamp") and time.time() - cache_data["timestamp"] < 3600:
                        logger.info(f"Using cached result for query: {query}")
                        return cache_data["result"]
                logger.info(f"Cache expired for query: {query}")
            except Exception as e:
                logger.warning(f"Cache load failed: {e}")

    # 执行搜索
    result = tavily_search(query, max_results, include_answer, search_depth)
    
    if cache_enabled:
        # 保存缓存
        cache_data = {
            "timestamp": time.time(),
            "result": result,
            "query": query
        }
        try:
            with open(cache_file, "wb") as f:
                pickle.dump(cache_data, f)
            logger.info(f"Cached result for query: {query}")
        except Exception as e:
            logger.warning(f"Cache save failed: {e}")
    
    return result


def tavily_search(query: str, max_results: int, include_answer: bool, 
                  search_depth: str) -> Dict:
    """执行 Tavily 搜索"""
    key = load_key()
    if not key:
        raise SystemExit(
            "Missing TAVILY_API_KEY. Set env var TAVILY_API_KEY or add it to ~/.openclaw/.env"
        )

    # 检查文件权限
    if not check_file_permissions():
        logger.warning("Config file has insecure permissions")

    payload = {
        "api_key": key,
        "query": query,
        "max_results": max_results,
        "search_depth": search_depth,
        "include_answer": bool(include_answer),
        "include_images": False,
        "include_raw_content": False,
    }

    data = json.dumps(payload).encode("utf-8")
    
    max_attempts = 3
    for attempt in range(max_attempts):
        try:
            req = urllib.request.Request(
                TAVILY_URL,
                data=data,
                headers={"Content-Type": "application/json", "Accept": "application/json"},
                method="POST",
            )

            with urllib.request.urlopen(req, timeout=30) as resp:
                body = resp.read().decode("utf-8", errors="replace")
                
            try:
                obj = json.loads(body)
            except json.JSONDecodeError:
                logger.error(f"API returned non-JSON response: {body[:300]}")
                raise SystemExit(f"Tavily returned non-JSON: {body[:300]}")

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

        except urllib.error.URLError as e:
            logger.warning(f"URL error (attempt {attempt + 1}/{max_attempts}): {e}")
            if attempt < max_attempts - 1:
                time.sleep(1)  # 等待后重试
                continue
            else:
                logger.error(f"Request failed after {max_attempts} attempts: {e}")
                raise SystemExit(f"Failed to connect to Tavily: {e}")
        except Exception as e:
            logger.error(f"Unexpected error: {e}")
            raise SystemExit(f"Search failed: {e}")


def to_brave_like(obj: Dict) -> Dict:
    """转换为 Brave-like 格式"""
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


def to_markdown(obj: Dict) -> str:
    """转换为 Markdown 格式"""
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


def to_html(obj: Dict) -> str:
    """转换为 HTML 格式"""
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


def main():
    """主函数"""
    ap = argparse.ArgumentParser(
        description="Tavily Search Tool with caching and retry mechanisms"
    )
    ap.add_argument("--query", required=True, help="Search query")
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
                    help="Output format: raw (default) | brave (title/url/snippet) | md (markdown) | html")
    ap.add_argument("--verbose", action="store_true", help="Enable verbose logging")

    args = ap.parse_args()

    if args.verbose:
        logger.setLevel(logging.DEBUG)

    # 限制结果数量
    max_results = max(1, min(args.max_results, 10))

    # 执行搜索
    cache_dir = args.cache_dir if not args.no_cache else None
    if cache_dir:
        res = tavily_search_with_cache(
            query=args.query,
            max_results=max_results,
            include_answer=args.include_answer,
            search_depth=args.search_depth,
            cache_dir=cache_dir
        )
    else:
        res = tavily_search(
            query=args.query,
            max_results=max_results,
            include_answer=args.include_answer,
            search_depth=args.search_depth
        )

    # 格式转换
    if args.format == "md":
        sys.stdout.write(to_markdown(res))
        return

    if args.format == "html":
        sys.stdout.write(to_html(res))
        return

    if args.format == "brave":
        res = to_brave_like(res)

    json.dump(res, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()