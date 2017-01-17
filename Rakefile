require 'pathname'
require 'shellwords'

RootDir = Pathname.new(Rake.application.original_dir)
DestDir = Pathname.new(Rake.application.original_dir + '-pristine')
BuildDir = RootDir.join('build')

desc 'Copy necessary files to new bundle'
task :default do
  rm_rf DestDir
  mkdir_p DestDir
  rm_rf BuildDir
  mkdir_p BuildDir

  [
    'emoji.rb',
    'icon.png',
    'emoji-db/emoji-db.json',
    'emoji-db/emoji-img/',
    'emoji-db/utils.rb',
  ].each do |f|
    dir_name = File.dirname(f)
    mkdir_p(DestDir.join dir_name) if dir_name != '.'
    cp_r RootDir.join(f), DestDir.join(f)
  end

  plist_contents = File.read(RootDir.join('info.plist'))

  File.open(DestDir.join('info.plist'), 'w', 0644) do |f|
    f.write plist_contents.gsub(
      'Find Dat Emoji DEV',
      'Find Dat Emoji'
    ).gsub(
      'testmoji',
      'emoji'
    ).gsub(
      'fm.meyer.FindDatEmojiDev',
      'fm.meyer.FindDatEmoji'
    )
  end

  chdir DestDir
  system(
    'zip',
    '-r9',
    BuildDir.join('find-emoji.alfredworkflow').to_s,
    '.'
  )
end
