import os
import shutil
import glob
from typing import Dict, Any, List, Optional
from config import USER_DOCUMENTS_DIR

USER_HOME_DIR = os.path.expanduser("~")

def get_base_dir(folder_key: str) -> str:
    f_lower = folder_key.lower()
    folder_name = "Documents"
    if f_lower in ["desktop", "desk"]:
        folder_name = "Desktop"
    elif f_lower in ["downloads", "download"]:
        folder_name = "Downloads"
    elif f_lower in ["pictures", "picture", "images", "photos"]:
        folder_name = "Pictures"
    elif f_lower in ["music", "songs"]:
        folder_name = "Music"
    elif f_lower in ["videos", "movies"]:
        folder_name = "Videos"
    elif f_lower in ["document", "documents", "doc", "docs"]:
        folder_name = "Documents"
        
    onedrive_path = os.path.join(USER_HOME_DIR, "OneDrive", folder_name)
    if os.path.exists(onedrive_path):
        return onedrive_path
        
    local_path = os.path.join(USER_HOME_DIR, folder_name)
    if os.path.exists(local_path):
        return local_path
        
    return os.path.join(USER_HOME_DIR, folder_name)

def resolve_user_path(path: str) -> str:
    if not path:
        return get_base_dir("Documents")
    
    path_str = os.path.expanduser(path).replace("\\", "/").strip()
    parts = [p for p in path_str.split("/") if p]
    
    if not parts:
        return get_base_dir("Documents")
        
    first_lower = parts[0].lower()
    known_folders = ["desktop", "desk", "downloads", "download", "documents", "document", "doc", "docs", "pictures", "picture", "music", "videos"]
    
    if first_lower in known_folders:
        base_dir = get_base_dir(first_lower)
        sub_parts = parts[1:]
        return os.path.join(base_dir, *sub_parts) if sub_parts else base_dir
    
    if os.path.isabs(path):
        return path
        
    return os.path.join(get_base_dir("Documents"), *parts)

def search_files(query: str, directory: Optional[str] = None) -> Dict[str, Any]:
    target_dir = resolve_user_path(directory) if directory else USER_DOCUMENTS_DIR
    matches = []
    if os.path.exists(target_dir):
        for root, dirs, files in os.walk(target_dir):
            for file in files:
                if query.lower() in file.lower():
                    matches.append(os.path.join(root, file))
    return {"query": query, "target_directory": target_dir, "matches": matches[:20]}

def read_file(path: str) -> Dict[str, Any]:
    full_path = resolve_user_path(path)
    if not os.path.exists(full_path):
        return {"error": f"File not found: {full_path}"}
    with open(full_path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read(5000)
    return {"path": full_path, "content": content}

def create_folder(path: str) -> Dict[str, Any]:
    full_path = resolve_user_path(path)
    if os.path.exists(full_path):
        return {
            "status": "ALREADY_EXISTS",
            "message": f"Folder '{os.path.basename(full_path)}' already exists at: {full_path}",
            "created_folder": full_path,
            "already_existed": True
        }
    os.makedirs(full_path, exist_ok=True)
    return {"status": "SUCCESS", "created_folder": full_path, "already_existed": False}

def create_file(path: str, content: str = "") -> Dict[str, Any]:
    full_path = resolve_user_path(path)
    os.makedirs(os.path.dirname(full_path), exist_ok=True)
    with open(full_path, "w", encoding="utf-8") as f:
        f.write(content)
    return {"status": "SUCCESS", "created_file": full_path}

def move_file(source: str, destination: str) -> Dict[str, Any]:
    src_full = resolve_user_path(source)
    dst_full = resolve_user_path(destination)
    if not os.path.exists(src_full):
        return {"error": f"Source file does not exist: {src_full}"}
    os.makedirs(os.path.dirname(dst_full), exist_ok=True)
    shutil.move(src_full, dst_full)
    return {"status": "SUCCESS", "moved_from": src_full, "moved_to": dst_full}

def copy_file(source: str, destination: str) -> Dict[str, Any]:
    src_full = resolve_user_path(source)
    dst_full = resolve_user_path(destination)
    if not os.path.exists(src_full):
        return {"error": f"Source file does not exist: {src_full}"}
    os.makedirs(os.path.dirname(dst_full), exist_ok=True)
    shutil.copy2(src_full, dst_full)
    return {"status": "SUCCESS", "copied_from": src_full, "copied_to": dst_full}

def delete_file(path: str) -> Dict[str, Any]:
    full_path = resolve_user_path(path)
    if not os.path.exists(full_path):
        return {"error": f"File does not exist: {full_path}"}
    if os.path.isdir(full_path):
        shutil.rmtree(full_path)
    else:
        os.remove(full_path)
    return {"status": "SUCCESS", "deleted_path": full_path}
