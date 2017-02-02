#!/usr/bin/env ruby
# encoding: utf-8

require 'tmpdir'
require 'optparse'
require 'json'
require 'cgi'
require 'shellwords'
require './emoji-db/utils.rb'
require 'pathname'

SPLITTER = '|'

def putv(*_); end

def codepoints_to_ruby(arr); arr.map(&:to_i).int_to_hex.map {|d| "\\u{#{d}}"}.join(''); end
def codepoints_to_emoji(arr); arr.map(&:to_i).pack('U*'); end

STDERR.puts '===='
STDERR.puts "ARGV: #{ARGV}"
STDERR.puts '===='

OptionParser.new do |opts|
  opts.program_name = File.basename(__FILE__)
  opts.summary_indent = "  "
  opts.summary_width = 20

  opts.on("-x", "--xml", "Output XML") do |o|
    $output_xml = true
  end

  opts.on("--to-name [string]", "Extract emojilib name from specially-formatted string") do |cp|
    print cp.split(SPLITTER)[0]
    abort
  end

  opts.on("--to-key [string]", "Print emoji-db key") do |cp|
    print cp.split(SPLITTER)[1]
    STDERR.puts cp.split(SPLITTER)[1]
    abort
  end

  opts.on("--to-path [string]", "Print path to emoji image") do |cp|
    print cp.split(SPLITTER)[2]
    STDERR.puts cp.split(SPLITTER)[2]
    abort
  end

  opts.on("--to-unicode [string]", "Convert codepoints to emoji") do |cp|
    print codepoints_to_emoji(cp.split(SPLITTER)[3..-1])
    abort
  end

  opts.on("--to-ruby [string]", "Convert codepoints to ruby") do |cp|
    print codepoints_to_ruby(cp.split(SPLITTER)[3..-1])
    abort
  end

  opts.on("-t", "--tone [1-5]", ['1','2','3','4','5'], "Include skin tone") do |t|
    $skin_tone = t.to_i
  end

  opts.on("-d", "--debug", "Run in debug mode (no cache)") do |o|
    STDERR.puts "Debug mode enabled"
    $debug_mode = true
  end

  opts.on("-v", "--verbose", "(Pretty self-explanatory)") do |o|
    def putv(*args); STDERR.puts args.map {|a| "#{a}".console_grey}.join("\n") + "\n"; end
  end
end.parse!(ARGV)

def items2xml(results)
  bits = results.map do |r|
    <<-ITEM
  <item
    arg="#{r[:arg]}"
    uid="#{r[:uid]}">
    <title>#{r[:title]}</title>
    <subtitle>#{r[:subtitle]}</subtitle>
    <subtitle mod="alt">#{r[:subtitle_alt]}</subtitle>
    <subtitle mod="ctrl">#{r[:subtitle_ctrl]}</subtitle>
    <subtitle mod="shift">#{r[:subtitle_shift]}</subtitle>
    <subtitle mod="cmd">#{r[:subtitle_cmd]}</subtitle>
    <icon>#{r[:path]}</icon>
  </item>
    ITEM
  end

  <<-XML
<?xml version='1.0'?>
<items>
#{bits.join("\n")}
</items>
  XML
end

EMOJI_DB_PATH = Pathname.new('./emoji-db/')
MARSHAL_TMP_FILE = File.expand_path('./alfred-emoji-marshal-cache', Dir.tmpdir)

EMOJIS = File.open(MARSHAL_TMP_FILE, File::RDWR|File::CREAT, 0644) do |f|
  begin
    raise if $debug_mode
    guts = Marshal.load(f.read)
    STDERR.puts "LOADING FROM MARSHAL: #{MARSHAL_TMP_FILE}"
    guts
  rescue
    STDERR.puts "LOADING FROM EMOJI-DB"
    fc = {
      'search_strings' => {},
      'db' => JSON.load(IO.read(EMOJI_DB_PATH.join('emoji-db.json')))
    }

    fc['db'].each do |k, v|
      fc['db'][k]['name'] = CGI.escapeHTML(fc['db'][k]['name'] || '')
      fc['search_strings'][k] = [
        v['name'].split(/\s+/),
        v['keywords'],
        v['codepoints'].map(&:to_unicode),
        fc['db'][k]['fitz'] ? 'fitz' : [],
      ].compact.join(' ').downcase
      fc['db'][k]['image'] = EMOJI_DB_PATH.join(fc['db'][k]['image'])
      if fc['db'][k]['fitz']
        fc['db'][k]['fitz'].map! {|p| EMOJI_DB_PATH.join(p)}
      end
    end
    f.rewind
    f.write(Marshal.dump(fc))
    f.flush
    f.truncate(f.pos)
    fc
  end
end

### SEARCH SHIT

matches = []

unless ARGV.empty?
  query = ARGV.join(' ').downcase
  STDERR.puts "QUERY: #{query}"
  if query.strip != ''
    EMOJIS['search_strings'].each do |key, ss|
      if ss.include?(query)
        matches.push key
        STDERR.puts "`#{EMOJIS['db'][key]['name']}` is a match!"
      end
    end
  end
end

items = matches.map do |emojilib_key|
  STDERR.puts "CODEPOINT: #{emojilib_key}"
  emoji = EMOJIS['db'][emojilib_key]

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

  STDERR.puts "KEYWORDS: #{EMOJIS['search_strings'][emojilib_key]}"
  STDERR.puts path

  codepoints = [
    *emoji['codepoints'],
    fitz,
  ].compact

  emojilib_name = emoji['emojilib_name'] ? ":#{emoji['emojilib_name']}:" : ''

  title = if emoji['name'] && emoji['name'].strip != ''
    emoji['name']
  else
    "NO NAME FOR EMOJI #{emojilib_key}"
  end

  {
    :arg => "#{emojilib_name}#{SPLITTER}#{emojilib_key}#{SPLITTER}#{path}#{SPLITTER}#{codepoints.join(SPLITTER)}",
    :uid => emojilib_key,
    :path => path,
    :title => title,
    :subtitle => "Copy #{codepoints_to_emoji(codepoints)} to clipboard",
    :subtitle_alt => "Copy #{codepoints_to_ruby(codepoints)} to clipboard",
    :subtitle_ctrl => "Copy #{emojilib_key} to clipboard",
    :subtitle_shift => emoji['emojilib_name'] ? "Copy #{emojilib_name} to clipboard" : "No emojilib name :..(",
    :subtitle_cmd => "Reveal image for #{codepoints_to_emoji(codepoints)} in Finder",
  }
end

if $output_xml
  STDERR.puts items2xml(items)
  puts items2xml(items)
else
  puts JSON.pretty_generate(items)
end
