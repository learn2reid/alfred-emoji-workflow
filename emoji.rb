#!/usr/bin/env ruby
# encoding: utf-8

require 'tmpdir'
require 'optparse'
require 'json'
require 'shellwords'
require 'pathname'

class Integer
  def to_unicode
    self.to_s(16).rjust(4, '0')
  end
end

class Array
  def to_codepoint_string
    self.map {|item| item.is_a?(Numeric) ? '0x' + item.to_unicode : item.to_s}.join(', ')
  end
end

PWD = Pathname.new File.expand_path(File.dirname(__FILE__))
EMOJI_DB_PATH = PWD.join('./emoji-db/')
MARSHAL_TMP_FILE = File.expand_path('./alfred-emoji-workflow-cache', Dir.tmpdir)

STDERR.puts '===='
STDERR.puts "ARGV: `#{ARGV}`"
STDERR.puts '===='

option_array = ARGV.join(' ').split

OptionParser.new do |opts|
  opts.program_name = File.basename(__FILE__)
  opts.summary_indent = "  "
  opts.summary_width = 20

  opts.on("-t", "--tone [number]", /^\d+$/, "Include skin tone") do |t|
    if t.to_i % 11 == 0
      $skin_tone = (t.to_i / 11).to_s
    else
      $skin_tone = t
    end
  end

  opts.on("-d", "--debug", "Run in debug mode (no cache)") do |_o|
    STDERR.puts "Debug mode enabled"
    $debug_mode = true
  end
end.parse!(option_array)

def reset_marshal_cache
  File.open(MARSHAL_TMP_FILE, File::RDWR|File::CREAT, 0644) do |f|
    fc = {
      'search_strings' => {},
      'db' => JSON.load(IO.read(EMOJI_DB_PATH.join('emoji-db.json')))
    }

    fc['db'].each do |k, v|
      puts [k, v]

      fc['db'][k]['name'] = fc['db'][k]['name'] || ''
      fc['search_strings'][k] = [
        '',
        (v['name'] || '').split,
        v['keywords'],
        v['codepoints'].map(&:to_unicode),
        fc['db'][k]['fitz'] ? 'fitz' : [],
        '',
      ].compact.join(' ').downcase

      if fc['db'][k]['image']
        fc['db'][k]['image'] = EMOJI_DB_PATH.join(fc['db'][k]['image'])
      else
        STDERR.puts "Emoji #{k} is missing an image"
      end

      if fc['db'][k]['fitz']
        fc['db'][k]['fitz'].each do |k, v|
          v.merge!({ 'image' => EMOJI_DB_PATH.join(v['image']) })
        end
      end
    end
    f.rewind
    f.write(Marshal.dump(fc))
    f.flush
    f.truncate(f.pos)
    fc
  end
end

if $debug_mode
  reset_marshal_cache
  STDERR.puts "Marshal cache reset!"
  puts JSON.pretty_generate({
    :items => [
      {
        :uid => '__debug__',
        :title => "Debug \u{1f41b}",
        :subtitle => "Emoji database has been reset",
      }
    ],
  })
  exit 0
end

EMOJI_OBJ = begin
  File.open(MARSHAL_TMP_FILE, File::RDWR|File::CREAT, 0644) {|f| Marshal.load(f.read)}
rescue ArgumentError
  STDERR.puts "Marshal cache could not be loaded. Resetting!"
  reset_marshal_cache
end

### SEARCH SHIT

exact_matches = []
matches = []

unless option_array.empty?
  query = option_array.join(' ').downcase.strip
  STDERR.puts "QUERY: `#{query}`"

  if query.strip == ''
    # show everything if no query is provided
    matches = EMOJI_OBJ['db'].keys
  else
    EMOJI_OBJ['search_strings'].each do |key, ss|
      if ss.include?(" #{query} ")
        exact_matches.push key
        STDERR.puts "`#{EMOJI_OBJ['db'][key]['name']}` is an exact match!"
      elsif ss.include?(query)
        matches.push key
        STDERR.puts "`#{EMOJI_OBJ['db'][key]['name']}` is a match!"
      end
    end
  end
end

STDERR.puts JSON.pretty_generate(ENV.to_h)

items = (exact_matches + matches).map do |emoji_key|
  STDERR.puts "CODEPOINT: `#{emoji_key}`"
  emoji = EMOJI_OBJ['db'][emoji_key]

  if $skin_tone && emoji['fitz'] && emoji['fitz'][$skin_tone]
    emoji = emoji['fitz'][$skin_tone]
  end

  path = emoji['image']
  codepoints = emoji['codepoints']

  STDERR.puts "KEYWORDS: `#{EMOJI_OBJ['search_strings'][emoji_key]}`"
  STDERR.puts path


  emojilib_name = emoji['emojilib_name'] ? ":#{emoji['emojilib_name']}:" : ''

  unicode_txt = codepoints.pack('U*')
  codepoint_txt = codepoints.to_codepoint_string

  subtitle = "Copy #{unicode_txt} to clipboard"
  mods = {
    :ctrl => {
      :valid => true,
      :arg => emoji_key,
      :subtitle => "Copy #{emoji_key} to clipboard",
      :variables => {
        :active_key => 'ctrl'
      },
    },
    :shift => {
      :valid => !!emoji['emojilib_name'],
      :arg => emoji['emojilib_name'],
      :subtitle => emoji['emojilib_name'] ? "Copy #{emojilib_name} to clipboard" : "No emojilib name :..(",
      :variables => {
        :active_key => 'shift'
      },
    },
    :alt => {
      :valid => true,
      :arg => codepoint_txt,
      :subtitle => "Copy '#{codepoint_txt}' to clipboard",
    },
    :cmd => {
      :valid => true,
      :arg => path,
      :subtitle => "Reveal image for #{unicode_txt} in Finder",
      :variables => {
        :active_key => 'cmd'
      },
    },
  }

  {
    :arg => unicode_txt,
    :uid => emoji_key,
    :variables => {},
    :icon => {
      :path => path,
    },
    # :type => 'file:skipcheck',
    :title => emoji['name'],
    :quicklookurl => path,
    :subtitle => subtitle,
    :mods => mods,
  }
end

puts JSON.pretty_generate({
  :items => items,
})
