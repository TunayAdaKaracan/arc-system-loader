function fetch_metadata(filename)
	return _fetch_metadata_from_file(_fstat(filename) == "folder" and filename.."/.info.pod" or filename)
end

function pod(obj, flags, meta)

    -- safety: fail if there are multiple references to the same table
    -- to do: allow this but write a reference marker in C code? maybe don't need to support that!
    local encountered = {}
    local function check(n)
        local res = false
        if (encountered[n]) return true
        encountered[n] = true
        for k,v in pairs(n) do
            if (type(v) == "table") res = res or check(v)
        end
        return res
    end
    if (type(obj) == "table" and check(obj)) then
        -- table is not a tree
        return nil, "error: multiple references to same table"
    end

    if (meta) then
        local meta_str = _generate_meta_str(meta)
        return _pod(obj, flags, meta_str) -- new meaning of 3rd parameter!
    end

    return _pod(obj, flags)
end

local function _generate_meta_str(meta_p)

    -- use a copy so that can remove pod_format without sideffect
    local meta = unpod(pod(meta_p)) or {}

    local meta_str = "--[["

    if (meta.pod_format and type(meta.pod_format) == "string") then
        meta_str ..= "pod_format=\""..meta.pod_format.."\""
        meta.pod_format = nil -- don't write twice
    elseif (meta.pod_type and type(meta.pod_type) == "string") then
        meta_str ..= "pod_type=\""..meta.pod_type.."\""
        meta.pod_type = nil -- don't write twice
    else
        meta_str ..= "pod"
    end

    local meta_str1 = _pod(meta, 0x0) -- 0x0: metadata always plain text. want to read it!

    if (meta_str1 and #meta_str1 > 2) then
        meta_str1 = string.sub(meta_str1, 2, #meta_str1-1) -- remove {}
        meta_str ..= ","
        meta_str ..= meta_str1
    end

    meta_str..="]]"

    return meta_str
end

function store_metadata(filename, meta)
    local old_meta = fetch_metadata(filename)
    
    if (type(old_meta) == "table") then
        if (type(meta) == "table") then			
            -- merge with existing metadata.   // to do: how to remove an item? maybe can't! just recreate from scratch if really needed.
            for k,v in pairs(meta) do
                old_meta[k] = v
            end
        end
        meta = old_meta
    end

    local meta_str = _generate_meta_str(meta)

    if (_fstat(filename) == "folder") then
        -- directory: write the .info.pod
        _store_metadata_str_to_file(filename.."/.info.pod", meta_str)
    else
        -- file: modify the metadata fork
        _store_metadata_str_to_file(filename, meta_str)
    end
end