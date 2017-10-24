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
  def to_ruby
    self.map(&:to_i).int_to_hex.map {|d| "\\u{#{d}}"}.join('')
  end

  def int_to_hex
    self.map {|item| item.is_a?(Numeric) ? item.to_unicode : item.to_s}
  end

  def to_emoji
    self.map(&:to_i).pack('U*')
  end
end

PWD = Pathname.new File.expand_path(File.dirname(__FILE__))
EMOJI_DB_PATH = PWD.join('./emoji-db/')
MARSHAL_TMP_FILE = File.expand_path('./alfred-emoji-marshal-cache', Dir.tmpdir)

STDERR.puts '===='
STDERR.puts "ARGV: `#{ARGV}`"
STDERR.puts '===='

option_array = ARGV.join(' ').split

OptionParser.new do |opts|
  opts.program_name = File.basename(__FILE__)
  opts.summary_indent = "  "
  opts.summary_width = 20

  opts.on("-t", "--tone [1-5]", ['1','2','3','4','5'], "Include skin tone") do |t|
    $skin_tone = t.to_i
  end

  opts.on("-d", "--debug", "Run in debug mode (no cache)") do |_o|
    STDERR.puts "Debug mode enabled"
    $debug_mode = true
  end
end.parse!(option_array)

if $debug_mode
  File.open(MARSHAL_TMP_FILE, File::RDWR|File::CREAT, 0644) do |f|
    fc = {
      'search_strings' => {},
      'db' => JSON.load(IO.read(EMOJI_DB_PATH.join('emoji-db.json')))
    }

    fc['db'].each do |k, v|
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
        fc['db'][k]['fitz'].map! {|p| EMOJI_DB_PATH.join(p)}
      end
    end
    f.rewind
    f.write(Marshal.dump(fc))
    f.flush
    f.truncate(f.pos)
  end

  puts JSON.pretty_generate({
    :items => [
      {
        # :arg => unicode_txt,
        :uid => '__debug__',
        :title => "Debug \u{1f41b}",
        :subtitle => "Emoji database has been reset",
      }
    ],
  })
  exit 0
end

EMOJI_OBJ = File.open(MARSHAL_TMP_FILE, File::RDWR|File::CREAT, 0644) {|f| Marshal.load(f.read)}

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

items = (exact_matches + matches).map do |emojilib_key|
  STDERR.puts "CODEPOINT: `#{emojilib_key}`"
  emoji = EMOJI_OBJ['db'][emojilib_key]

  path = emoji['image']
  codepoints = [emoji['codepoints']]

  fitz = if $skin_tone && emoji['fitz']
    [
      nil,
      0x1f3fb,
      0x1f3fc,
      0x1f3fd,
      0x1f3fe,
      0x1f3ff,
    ][$skin_tone]
  end

  path = emoji['fitz'][$skin_tone - 1] if fitz

  STDERR.puts "KEYWORDS: `#{EMOJI_OBJ['search_strings'][emojilib_key]}`"
  STDERR.puts path

  codepoints = [*emoji['codepoints'], fitz].compact

  emojilib_name = emoji['emojilib_name'] ? ":#{emoji['emojilib_name']}:" : ''

  unicode_txt = codepoints.to_emoji
  ruby_txt = codepoints.to_ruby

  {
    :arg => unicode_txt,
    :uid => emojilib_key,
    :icon => {
      :path => path,
    },
    # :type => 'file:skipcheck',
    :title => emoji['name'],
    :quicklookurl => path,
    :subtitle => "Copy #{unicode_txt} to clipboard",
    :mods => {
      :alt => {
        :valid => true,
        :arg => ruby_txt,
        :subtitle => "Copy #{ruby_txt} to clipboard"
      },
      :ctrl => {
        :valid => true,
        :arg => emojilib_key,
        :subtitle => "Copy #{emojilib_key} to clipboard"
      },
      :shift => {
        :valid => !!emoji['emojilib_name'],
        :arg => emoji['emojilib_name'],
        :subtitle => emoji['emojilib_name'] ? "Copy #{emojilib_name} to clipboard" : "No emojilib name :..("
      },
      :cmd => {
        :valid => true,
        :arg => path,
        :subtitle => "Reveal image for #{unicode_txt} in Finder"
      }
    }
  }
end

puts JSON.pretty_generate({
  :items => items,
})
