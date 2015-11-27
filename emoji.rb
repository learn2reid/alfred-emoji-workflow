#!/usr/bin/env ruby

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

  opts.on("-u", "--unicode", "Output XML") do |o|
    $copy_unicode = true
  end

  opts.on("-v", "--verbose", "(Pretty self-explanatory)") do |o|
    def putv(*args); STDERR.puts args.map {|a| "#{a}".console_grey}.join("\n") + "\n"; end
  end
end.parse!

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

EMOJIS = File.open('./marshal-cache', File::RDWR|File::CREAT, 0644) do |f|
  begin
    guts = Marshal.load(f.read)
    STDERR.puts "LOADING FROM MARSHALL"
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
        fc['db'][k]['image'] = File.join(EMOJI_DB_PATH, fc['db'][k]['images']['apple'])
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

query = Regexp.escape(ARGV.first)
matches = []

EMOJIS['search_strings'].each do |key, ss|
  if ss.match(/#{query}/)
    matches.push key
    STDERR.puts "#{EMOJIS['db'][key]['name']} is a match!"
  end
end

items = matches.map do |k|
  emoji = EMOJIS['db'][k]
  path = emoji['image']

  emoji_arg = $copy_unicode ? emoji['code'] : emoji['name']

  {
    :arg => emoji_arg,
    :uid => k,
    :path => path,
    :title => emoji['name'],
    :subtitle => "Copy #{emoji_arg} to clipboard",
  }
end

if $output_xml
  puts items2xml(items)
else
  puts JSON.pretty_generate(items)
end
