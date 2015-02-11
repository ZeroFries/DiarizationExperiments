require 'pty'
require 'expect'
require 'securerandom'
require 'diarize'

class AudioDiarize
	attr_accessor :path

	def initialize(path)
		@path = path
	end

	def process
		file_dir = split_audio
		p file_dir

		process_audio_files file_dir
	end

	def process_audio_files(dir)
		threads = []
		speakers = []
		t = Time.now
		Dir.glob("#{dir}/*.wav").each_with_index do |file_path, i|
			if i < 3
				threads << Thread.new(i) do
					speakers << parse_audio_file(file_path)
				end
			end
		end	
		threads.each {|t| t.join}
		speaker_1 = speakers.first.first[:speaker]
		speaker_2 = speakers.first.last[:speaker]
		speakers[1..-1].each do |speaker|
			
		end
		File.open('log.txt', 'w') do |f|
						f << "\n#{speakers.inspect}"
					end
		p "Took: #{Time.now - t}"

		speakers
	end

	protected

	# side effect: dir/file creation
	def split_audio
		dir = SecureRandom.uuid
		while Dir.exists?(dir) do
			dir = SecureRandom.uuid
		end
		Dir.mkdir dir

		dur = compute_audio_duration
		p dur
		# split in 10 minute chunks
		chunks = (dur / 600) + 1

		chunks.times do |n|
			length = (n+1)!=chunks ? 10 : (dur-(n*600))/60
			start = sec_to_duration_string n*600
			system "ffmpeg -i #{@path} -acodec copy -t 00:#{length}:00 -ss #{start} #{dir}/p-#{n}.wav"
		end

		# PTY.spawn("adintool -in file -out file -filename #{dir}/p -startid 0 -freq 44100 -lv 2048 -zc 30 -headmargin 600 -tailmargin 600") do |reader, writer|
		#   reader.expect(/enter filename/)
		#   writer.puts @path
		#   reader.expect(/enter filename/)
		#   reader.close
		# end

		dir
	end

	def compute_audio_duration
		dur_io = IO.popen("ffmpeg -i #{@path} 2>&1 | grep Duration", 'r+')
		dur_s = dur_io.read.match(/\d+:\d+:\d+/)[0]
		dur = duration_string_to_sec dur_s
	end

	def duration_string_to_sec(dur_s)
		h = dur_s[0..1].to_i
		m = dur_s[3..4].to_i
		s = dur_s[6..7].to_i
		(h * 3600) + (m * 60) + s
	end

	def sec_to_duration_string(s)
		Time.at(s).utc.strftime("%H:%M:%S")
	end

	def parse_audio_file(path)
		url = URI.join 'file:///', "#{Dir.pwd}/#{path}"
		audio = Diarize::Audio.new url
		p audio
		audio.analyze!

		audio.segments.map do |seg|
			{
				start: seg.start,
				duration: seg.duration,
				speaker: seg.speaker
			}
		end
	end

	def clean_files
	end


end

AudioDiarize.new('/home/zerofries/Music/FINAL_Peter_Diamandis_Bold_TFS.wav').process