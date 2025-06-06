local queries = require('qmk.parse.qmk.queries')
local get_inline_config = require('qmk.parse.get_inline_config')
local check = require('qmk.utils').check
local E = require('qmk.errors')
local ts = vim.treesitter

---@return qmk.Position
local function get_keymaps_position(root)
	local start, final = nil, nil
	local count = 0

	queries.declaration_visitor(root, {
		[queries.declaration_ids.declaration] = function(node)
			count = count + 1

			local row_start, _, row_end = node:range()
			start = row_start
			final = row_end
		end,
	})

	check(count <= 1, E.keymaps_too_many)
	check(count >= 1, E.keymaps_none)
	check(start and final, E.keymaps_none)
	check(start ~= final, E.keymaps_overlap)

	return { start = start, final = final }
end

---@return qmk.KeymapsList
local function get_keymaps(name, root, content)
	---@type qmk.KeymapsList
	local keymaps = {}

	---@type qmk.Keymap
	---@diagnostic disable-next-line: missing-fields
	local current_keymap = {
		layout_name = name,
		keys = {},
		config = {},
	}
	local ids = queries.keymap_ids

	queries.keymap_visitor(name, root, content, {
		[ids.keymap_name] = function(node) --
			current_keymap.layer_name = ts.get_node_text(node, content)
		end,

		[ids.key_list] = function(node)
			local row_start, _, row_end = node:range()
			current_keymap.pos = { start = row_start, final = row_end }

			queries.key_visitor(node, {
				key = function(key_node)
					local key_text = ts.get_node_text(key_node, content)
					local newlines_removed = key_text:gsub('%s', ''):gsub(',', ', ')
					if key_text ~= '' then
						table.insert(current_keymap.keys, newlines_removed)
					end
				end,
			})
		end,

		[ids.final] = function(_)
			table.insert(keymaps, current_keymap)
			current_keymap = {
				layout_name = name,
				keys = {},
			}
		end,
	})

	return keymaps
end

---get all keymaps from the current buffer
---@param content string
---@param options qmk.Config
---@return qmk.Keymaps, qmk.InlineConfig | nil
local function get_keymap(content, options)
	local parser = ts.get_string_parser(content, 'c', {})
	local root = parser:parse()[1]:root()

	local inline_config = get_inline_config(queries.comment_visitor, root, content)
	local name = inline_config and inline_config.name or options.name

	return {
		pos = get_keymaps_position(root),
		keymaps = get_keymaps(name, root, content),
	},
		inline_config
end

return get_keymap
