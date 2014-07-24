#!/usr/bin/env ruby
#
# Manage a "resident set" of music on the Mac by selectively rsyncing stuff from winter
# downstairs. Automatically import and remove files from iTunes as I do so.

require 'yaml'
require 'colored'
require 'fileutils'
require 'shellwords'

LOCAL_DIR = "/Users/ashl6947/Music/winter"
REMOTE_DIRS = %w{
  /usr/local/ash-music
  /usr/local/jayne-music
}

Track = Struct.new(:path, :artist, :album)
Choice = Struct.new(:kind, :index, :name, :subname, :tracks) do
  def to_s
    desc = name.cyan.bold.underline
    desc << " by #{subname}" if subname
    "  [#{index.to_s.bold}] #{kind}: #{desc} (#{tracks.size})"
  end
end

# Interactively search for albums or tracks that match a given pattern.

print "Search for an #{'album'.bold} or an #{'artist'.bold}: "
search = gets.chomp.downcase

stdout = `ssh smash@winter 'find #{REMOTE_DIRS.join ' '} -name "*.mp3" | grep -i "#{search}"'`
tracks = stdout.scrub.split(/\n/).map do |path|
  parts = path.split(%r{/})
  Track.new(path, parts[-3], parts[-2])
end.select { |t| t.artist.downcase.include?(search) || t.album.downcase.include?(search) }

matching_artists = tracks.map(&:artist).sort.uniq
matching_albums = tracks.map(&:album).sort.uniq

choices = []
index = 0
choices += matching_artists.map do |artist|
  mtracks = tracks.select { |t| t.artist == artist }
  i = index
  index += 1
  Choice.new(:artist, i, artist, nil, mtracks)
end
choices += matching_albums.map do |album|
  mtracks = tracks.select { |t| t.album == album }
  i = index
  index += 1
  Choice.new(:album, i, album, mtracks[0].artist, mtracks)
end

puts
puts "Matching choices:"
puts
puts choices.map(&:to_s).join("\n")
puts

print "Choose a selection: "
chosen_s = gets.chomp
unless chosen_s =~ /\d+/
  puts "Please enter a number!"
  exit 1
end
chosen = chosen_s.to_i
unless chosen >= 0 and chosen < choices.size
  puts "Please choose a valid index!"
  exit 1
end
choice = choices[chosen]

# Fetch ye tracks

puts
puts "Fetching chosen tracks."
puts

dest_paths = []
choice.tracks.each do |track|
  dest_dir = File.join(LOCAL_DIR, track.artist, track.album)
  dest_path = File.join(dest_dir, File.basename(track.path))
  dest_paths << dest_path
  FileUtils.mkdir_p dest_dir

  `scp 'smash@winter:\"#{track.path}\"' '#{dest_path}'`
  unless $?.success?
    puts "Unable to copy #{track.path} to #{dest_path}!"
    exit 1
  end

  print '.'
  $stdout.flush
end
puts

plural = choice.tracks.size == 1 ? "track" : "tracks"
puts "Complete. #{choice.tracks.size} #{plural} transferred."

cmdlines = ['tell application "iTunes"']
dest_paths.each do |path|
  cmdlines << "  add (POSIX file \"#{path}\")"
end
cmdlines << 'end tell'
command = cmdlines.join "\n"

puts
puts "Adding tracks to iTunes."
puts

system "osascript -e '#{command}'"

puts "Complete."
