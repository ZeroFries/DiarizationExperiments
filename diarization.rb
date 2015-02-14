require 'pty'
require 'expect'
require 'securerandom'
require 'diarize'

class AudioDiarize
	attr_accessor :path

	AUDIO_CHUNK_LENGTH = 3000 # 5 mins
	AUDIO_INTERVAL_LENGTH = 3
	AUDIO_SKIP_LENGTH = 2

	# skew = 1/(3/5) = 1.666

	def initialize(path)
		@path = path
	end

	def process
		file_dir = split_audio
		p file_dir

		process_audio_files file_dir
	end

	def process_audio_files(dir)
		segments = []
		speakers = []
		t = Time.now
		Dir.glob("#{dir}/*.wav").each_slice(4) do |files|
			# parse audio in batches of 4
			threads = []	
			files.each_with_index do |file_path, i|
				threads << Thread.new(i) do
					segments += parse_audio_file(file_path)
				end
			end
			threads.each {|t| t.join}

			segments.each do |seg|
				if speakers.empty?
					speakers << seg[:speaker]
				else
					# future improvement: find matched speaker and change 
					# every ref to that speaker to matched in one go
					if matched_speaker = find_matching_speaker(speakers, seg[:speaker])
						seg[:speaker] = matched_speaker
					else
						speakers << seg[:speaker]
					end
				end
			end
		end

		File.open("log-#{dir}.txt", 'w') do |f|
			segments.sort_by {|seg| seg[:start]}.each do |seg|
				if @previous_speaker != seg[:speaker]
					@previous_speaker = seg[:speaker]
					f << "\nStart: #{sec_to_duration_string seg[:start]}, Speaker: #{speakers.index(seg[:speaker])}"
				end
			end
			f << "\nTook: #{Time.now - t}"
		end

		speakers
	end

	protected

	def find_matching_speaker(speakers, speaker)
		matched_speaker = nil
		speakers.each do |s|
			matched_speaker = s if speaker.same_speaker_as s
			break if matched_speaker
		end
		matched_speaker
	end

	# side effect: dir/file creation
	def split_audio
		dir = SecureRandom.uuid
		while Dir.exists?(dir) do
			dir = SecureRandom.uuid
		end
		Dir.mkdir dir

		dur = compute_audio_duration
		# split in 10 minute chunks
		chunks = (dur / 600) + 1

		chunks.times do |n|
			length = (n+1)!=chunks ? 10 : (dur-(n*600))/60
			start = sec_to_duration_string n*600
			system "ffmpeg -i #{@path} -acodec copy -t 00:#{length}:00 -ss #{start} #{dir}/p-#{n}.wav"
		end

		dir
	end

	# def regroup_audio(dir)
	# 	files_per_chunk = 
	# end

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
		audio.analyze!

		audio.segments.map do |seg|
			{
				start: seg.start,
				duration: seg.duration,
				speaker: seg.speaker
			}
		end.sort_by {|seg| seg[:start]}
	end

	def clean_files
	end


end

AudioDiarize.new('/home/zerofries/Music/podcast_sample.wav').process