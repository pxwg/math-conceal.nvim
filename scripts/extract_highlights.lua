#!/usr/bin/env lua
---Simple Typst highlight groups extractor
---Extract highlight groups (with @ prefix) from .scm files

local cjson = require("cjson")
local lfs = require("lfs")

local HighlightExtractor = {}
HighlightExtractor.__index = HighlightExtractor

function HighlightExtractor.new(queries_dir)
    local self = setmetatable({}, HighlightExtractor)
    self.queries_dir = queries_dir or "queries_config"
    self.all_groups = {}
    self.language_groups = {}
    return self
end

function HighlightExtractor:extract_all_highlights()
    -- Extract highlight groups from all languages
    if not self:_directory_exists(self.queries_dir) then
        print(string.format("Directory %s does not exist!", self.queries_dir))
        return {}
    end

    local language_dirs = {}
    for dir in lfs.dir(self.queries_dir) do
        if dir ~= "." and dir ~= ".." then
            local path = self.queries_dir .. "/" .. dir
            local attr = lfs.attributes(path)
            if attr and attr.mode == "directory" then
                table.insert(language_dirs, { name = dir, path = path })
            end
        end
    end

    print(string.format("Found %d language directories", #language_dirs))

    for _, lang_info in ipairs(language_dirs) do
        local language = lang_info.name
        self.language_groups[language] = {}

        local scm_files = self:_get_scm_files(lang_info.path)
        print(string.format("Processing %s: %d .scm files", language, #scm_files))

        for _, scm_file in ipairs(scm_files) do
            self:_extract_from_file(scm_file, language)
        end
    end

    -- Convert sets to sorted arrays
    for language, groups in pairs(self.language_groups) do
        self.language_groups[language] = self:_sort_table(groups)
    end

    return self.language_groups
end

function HighlightExtractor:_extract_from_file(file_path, language)
    -- Extract highlight groups from a single file
    local success, content = pcall(self._read_file, self, file_path)
    if not success then
        print(string.format("Error reading %s: %s", file_path, content))
        return
    end

    -- Find all @ prefixed highlight groups using Lua patterns
    for match in content:gmatch("@([a-zA-Z_][a-zA-Z0-9_]*)") do
        local group_name = "@" .. match
        self.all_groups[group_name] = true
        self.language_groups[language][group_name] = true
    end
end

function HighlightExtractor:generate_markdown()
    -- Generate markdown with highlight groups by language
    local lines = {
        "# Highlight Groups by Language",
        "",
        string.format("Total: %d highlight groups across %d languages",
            self:_table_length(self.all_groups),
            self:_table_length(self.language_groups)),
        ""
    }

    -- Get sorted list of languages
    local languages = {}
    for lang, _ in pairs(self.language_groups) do
        table.insert(languages, lang)
    end
    table.sort(languages)

    -- Add language sections
    for _, language in ipairs(languages) do
        local groups = self.language_groups[language]
        table.insert(lines, "## " .. self:_title_case(language))
        table.insert(lines, "")
        table.insert(lines, string.format("Count: %d highlight groups", #groups))
        table.insert(lines, "")

        for _, group in ipairs(groups) do
            table.insert(lines, "- " .. group)
        end
        table.insert(lines, "")
    end

    return table.concat(lines, "\n")
end

function HighlightExtractor:generate_json()
    -- Generate JSON data with highlight groups by language
    local all_groups_list = {}
    for group, _ in pairs(self.all_groups) do
        table.insert(all_groups_list, group)
    end
    table.sort(all_groups_list)

    -- Convert language groups from table to array
    local lang_groups_formatted = {}
    for lang, groups in pairs(self.language_groups) do
        lang_groups_formatted[lang] = groups
    end

    return {
        total_count = #all_groups_list,
        languages = lang_groups_formatted,
        all_highlight_groups = all_groups_list
    }
end

function HighlightExtractor:save_results(output_dir)
    -- Save results to highlight folder
    output_dir = output_dir or "highlights"

    if not self:_directory_exists(output_dir) then
        lfs.mkdir(output_dir)
    end

    -- Save markdown file
    local markdown_content = self:generate_markdown()
    self:_write_file(output_dir .. "/highlights.md", markdown_content)

    -- Save JSON file
    local json_data = self:generate_json()
    local json_content = cjson.encode(json_data)
    self:_write_file(output_dir .. "/highlights.json", json_content)

    print(string.format("Results saved to %s/", output_dir))
    print("- highlights.md: Highlight groups by language")
    print("- highlights.json: JSON data")
end

-- Helper methods
function HighlightExtractor:_directory_exists(path)
    local attr = lfs.attributes(path)
    return attr and attr.mode == "directory"
end

function HighlightExtractor:_get_scm_files(dir_path)
    local files = {}
    for file in lfs.dir(dir_path) do
        if file:match("%.scm$") then
            table.insert(files, dir_path .. "/" .. file)
        end
    end
    return files
end

function HighlightExtractor:_read_file(file_path)
    local file, err = io.open(file_path, "r")
    if not file then
        error(err)
    end
    local content = file:read("*a")
    file:close()
    return content
end

function HighlightExtractor:_write_file(file_path, content)
    local file, err = io.open(file_path, "w")
    if not file then
        error(err)
    end
    file:write(content)
    file:close()
end

function HighlightExtractor:_sort_table(table_as_set)
    local array = {}
    for key, _ in pairs(table_as_set) do
        table.insert(array, key)
    end
    table.sort(array)
    return array
end

function HighlightExtractor:_table_length(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

function HighlightExtractor:_title_case(str)
    return str:gsub("^%l", string.upper)
end

-- Main function
print("Typst Highlight Groups Extractor")
print(string.rep("=", 40))

local extractor = HighlightExtractor.new()
local highlights = extractor:extract_all_highlights()

if extractor:_table_length(highlights) == 0 then
    print("No highlight groups found!")
    return
end

print(string.format("\nFound %d highlight groups across %d languages:",
    extractor:_table_length(extractor.all_groups),
    extractor:_table_length(highlights)))

for language, groups in pairs(highlights) do
    print(string.format("  %s: %d groups", language, #groups))
end

-- Save results
extractor:save_results()
