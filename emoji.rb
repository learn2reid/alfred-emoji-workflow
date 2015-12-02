#!/usr/bin/env ruby
# encoding: utf-8

require 'tmpdir'
require 'optparse'
require 'json'

def putv(*_); end

def emoji_to_codepoints(uni)
  uni.chars.map do |c|
    "%04x" % c.unpack('U')[0]
  end.delete_if do |c|
    c === 'fe0f'
  end
end

def codepoints_to_ruby(arr);  arr.map {|u| "\\u{#{u}}"}.join(''); end
def codepoints_to_unicode(arr); arr.map {|u| [u.hex].pack('U')}.join(''); end

OptionParser.new do |opts|
  opts.program_name = File.basename(__FILE__)
  opts.summary_indent = "  "
  opts.summary_width = 20

  opts.on("-x", "--xml", "Output XML") do |o|
    $output_xml = true
  end

  opts.on("--to-ruby [JSON object]", "Convert codepoints to ruby") do |cp|
    print codepoints_to_ruby(JSON.parse(cp)['codepoints'])
    abort
  end

  opts.on("--to-unicode [JSON object]", "Convert codepoints to emoji") do |cp|
    print codepoints_to_unicode(JSON.parse(cp)['codepoints'])
    abort
  end

  opts.on("--to-name [JSON object]", "Extract emojilib name from JSON object") do |cp|
    print JSON.parse(cp)['emojilib']
    abort
  end

  opts.on("-t", "--tone [1-6]", ['1','2','3','4','5','6'], "Include skin tone") do |t|
    $skin_tone = [
      nil,
      "1f3fb",
      "1f3fb",
      "1f3fc",
      "1f3fd",
      "1f3fe",
      "1f3ff",
    ][t.to_i]
  end

  opts.on("-d", "--debug", "Run in debug mode (no cache)") do |o|
    STDERR.puts "Debug mode enabled"
    $debug_mode = true
  end

  opts.on("-v", "--verbose", "(Pretty self-explanatory)") do |o|
    def putv(*args); STDERR.puts args.map {|a| "#{a}".console_grey}.join("\n") + "\n"; end
  end
end.parse!

def items2xml(results)
  results.map! do |r|
    <<-ITEM
  <item arg='#{r[:arg]}' uid="#{r[:uid]}">
    <title>#{r[:title]}</title>
    <subtitle>#{r[:subtitle]}</subtitle>
    <subtitle mod="alt">#{r[:subtitle_alt]}</subtitle>
    <subtitle mod="shift">#{r[:subtitle_shift]}</subtitle>
    <icon>#{r[:path]}</icon>
  </item>
    ITEM
  end

  <<-XML
<?xml version='1.0'?>
<items>
#{results.join}
</items>
  XML
end

EMOJI_DB_PATH = File.expand_path('./emoji-db/')

MARSHAL_TMP_FILE = File.expand_path('./alfred-emoji-marshal-cache', Dir.tmpdir)

EMOJIS = File.open(MARSHAL_TMP_FILE, File::RDWR|File::CREAT, 0644) do |f|
  begin
    raise if $debug_mode
    guts = Marshal.load(f.read)
    STDERR.puts "LOADING FROM MARSHAL"
    guts
  rescue
    STDERR.puts "LOADING FROM EMOJI-DB"
    fc = {
      'search_strings' => {},
      'db' => JSON.load(IO.read(File.expand_path('emoji-db.json', EMOJI_DB_PATH)))
    }

    fc['db'].each do |k, v|
      fc['search_strings'][k] = (v['name'].split(/\s+/) | v['keywords']).join(' ')
      if fc['db'][k]['images']['apple']
        fc['db'][k]['image'] = File.expand_path(fc['db'][k]['images']['apple'], EMOJI_DB_PATH)
      else
        STDERR.puts "No image at db[#{k}][images][apple] :..("
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
  query = ARGV.map {|a| Regexp.escape(a)}.join('|')
  STDERR.puts "QUERY: #{query}"
  EMOJIS['search_strings'].each do |key, ss|
    if ss.match(/#{query}/)
      matches.push key
      STDERR.puts "#{EMOJIS['db'][key]['name']} is a match!"
    end
  end
end

items = matches.map do |codepoint|
  emoji = EMOJIS['db'][codepoint]
  path = emoji['image']

  d = {}

  d[:codepoints] = [
    *emoji_to_codepoints(emoji['code']),
    $skin_tone,
    "fe0f",
  ].compact

  d[:emojilib] = emoji['emojilib_name'] ? ":#{emoji['emojilib_name']}:" : ''

  {
    :arg => JSON.generate(d),
    :uid => codepoint,
    :path => path,
    :title => emoji['name'],
    :subtitle => "Copy #{codepoints_to_unicode(d[:codepoints])} to clipboard",
    :subtitle_alt => "Copy #{codepoints_to_ruby(d[:codepoints])} to clipboard",
    :subtitle_shift => emoji['emojilib_name'] ? "Copy #{d[:emojilib]} to clipboard" : "No emojilib name :..(",
  }
end

if $output_xml
  puts items2xml(items)
else
  puts JSON.pretty_generate(items)
end
