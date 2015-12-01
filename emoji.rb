#!/usr/bin/env ruby

require 'tmpdir'
require 'optparse'
require 'json'

def putv(*_); end

OptionParser.new do |opts|
  opts.program_name = File.basename(__FILE__)
  opts.summary_indent = "  "
  opts.summary_width = 20

  opts.on("-x", "--xml", "Output XML") do |o|
    $output_xml = true
  end

  opts.on("-r", "--ruby", "Copy as Ruby unicode string") do |o|
    $copy_as_ruby = true
  end

  opts.on("-t", "--tone [1-6]", ['1','2','3','4','5','6'], "Include skin tone") do |t|
    $skin_tone = [
      "",
      "\u{1f3fb}",
      "\u{1f3fb}",
      "\u{1f3fc}",
      "\u{1f3fd}",
      "\u{1f3fe}",
      "\u{1f3ff}",
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

$skin_tone ||= ''

def items2xml(results)
  results.map! do |r|
    <<-ITEM
  <item arg="#{r[:arg]}" uid="#{r[:uid]}">
    <title>#{r[:title]}</title>
    <subtitle>#{r[:subtitle]}</subtitle>
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

MARSHAL_TMP_FILE = File.join(Dir.tmpdir, './alfred-emoji-marshal-cache')

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
      'db' => JSON.load(IO.read(File.join(EMOJI_DB_PATH, 'emoji-db.json')))
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

items = matches.map do |k|
  emoji = EMOJIS['db'][k]
  path = emoji['image']

  if $copy_as_ruby
    # split multi
    arg = k.split('_').map {|e| "\\u{#{e}}"}.join('')
  else
    # \uFE0F: emoji variation selector
    arg = emoji['code'] + $skin_tone + "\uFE0F"
  end

  {
    :arg => arg,
    :uid => k,
    :path => path,
    :title => emoji['name'],
    :subtitle => "Copy #{arg} to clipboard"
  }
end

if $output_xml
  puts items2xml(items)
else
  puts JSON.pretty_generate(items)
end
