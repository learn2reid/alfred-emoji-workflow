require 'tmpdir'

desc 'Copy necessary files to new bundle'
task :default do
  RSYNC_SRC = Dir.pwd
  RSYNC_DEST = "#{RSYNC_SRC}-pristine"

  # FileUtils.rm_rf RSYNC_DEST
  FileUtils.mkdir_p RSYNC_DEST

  [
    'README.md',
    'emoji.rb',
    'icon.png',
    'emoji-db/emoji-db.json',
    'emoji-db/emoji-img/',
  ].each do |f|
    Dir.chdir RSYNC_DEST
    dir_name = File.dirname(f)

    FileUtils.mkdir_p(dir_name) if dir_name != '.'
    FileUtils.cp_r File.expand_path(f, RSYNC_SRC), dir_name
  end

  plist_guts = IO.read(File.expand_path('info.plist', RSYNC_SRC))
  File.open(File.expand_path('info.plist', RSYNC_DEST), File::RDWR|File::CREAT, 0644) do |f|
    f.write plist_guts.gsub(
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

  Dir.chdir RSYNC_DEST
  system(
    'zip',
    '-r9',
    File.expand_path('./package/emoji-codes.alfredworkflow', RSYNC_SRC),
    '.'
  )
end
