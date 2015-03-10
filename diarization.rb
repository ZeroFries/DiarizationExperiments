require 'pty'
require 'expect'
require 'securerandom'
require 'diarize'

class AudioDiarize
	attr_accessor :path

	AUDIO_CHUNK_LENGTH = 300 # 5 mins
	AUDIO_INTERVAL_LENGTH = 4
	AUDIO_SKIP_LENGTH = 1

	# skew = 1/(3/5) = 1.666

	def initialize(path)
		@path = path
	end

	def process
		@t = Time.now
		@skew = 1/(AUDIO_INTERVAL_LENGTH.to_f/(AUDIO_INTERVAL_LENGTH.to_f+AUDIO_SKIP_LENGTH.to_f))
		file_dir = split_audio

		process_audio_files file_dir
	end

	def process_audio_files(dir)
		segments = []
		speakers = []
		Dir.glob("#{dir}/*.wav").each_slice(4) do |files|
			# parse audio in batches of 4
			threads = []	
			files.each_with_index do |file_path, i|
				threads << Thread.new(i) do
					segments << parse_audio_file(file_path)
				end
			end
			threads.each {|t| t.join}
		end

		segments = segments.flatten

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

		File.open("log-#{dir}.txt", 'w') do |f|
			segments.sort_by {|seg| seg[:start]}.each do |seg|
				if @previous_speaker != seg[:speaker]
					@previous_speaker = seg[:speaker]
					f << "\nStart: #{sec_to_duration_string seg[:start]}, Speaker: #{speakers.index(seg[:speaker])}"
				end
			end
			f << "\nTook: #{Time.now - @t}"
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

		total_audio_interval = AUDIO_INTERVAL_LENGTH + AUDIO_SKIP_LENGTH
		dur = compute_audio_duration
		skewed_dur = (dur.to_f / @skew).to_i
		# 24 mins
		chunks = (skewed_dur / AUDIO_CHUNK_LENGTH) + 1
		# 5 chunks
		sub_chunk_count = (AUDIO_CHUNK_LENGTH.to_f / AUDIO_INTERVAL_LENGTH.to_f).to_i

		chunks.times.each_slice(4) do |batch|
			threads = []
			batch.each do |n|
				threads << Thread.new(n) do
					sub_dir = "sub-#{n}"
					Dir.mkdir "#{dir}/#{sub_dir}"
					length = (n+1)!=chunks ? AUDIO_CHUNK_LENGTH : (dur-(n*AUDIO_CHUNK_LENGTH))/60
					start = ((n * AUDIO_CHUNK_LENGTH) * @skew).to_i
					concat_cmd = "ffmpeg"
					sub_chunk_count.times do |c|
						sub_chunk_start = start + (c*total_audio_interval)
						break if (sub_chunk_start+AUDIO_INTERVAL_LENGTH) > dur
						concat_cmd << " -i #{dir}/#{sub_dir}/p-#{n}-#{c}.wav"
						system "ffmpeg -i #{@path} -acodec copy -t 00:00:0#{AUDIO_INTERVAL_LENGTH} -ss #{sec_to_duration_string sub_chunk_start} #{dir}/#{sub_dir}/p-#{n}-#{c}.wav"
					end
					file_count = Dir.glob("#{dir}/#{sub_dir}/*.wav").count
					concat_cmd << " -filter_complex '[0:0][1:0][2:0][3:0]concat=n=#{file_count}:v=0:a=1[out]' \
													-map '[out]' #{dir}/p-#{n}.wav"
					system concat_cmd
				end
				threads.each {|t| t.join}
			end
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
		file_number = path.match(/(p-)(\d+)/)[2]
		url = URI.join 'file:///', "#{Dir.pwd}/#{path}"
		
		audio = Diarize::Audio.new url
		audio.analyze!

		audio.segments.map do |seg|
			{
				start: compute_start(seg, file_number),
				duration: seg.duration,
				speaker: seg.speaker
			}
		end.sort_by {|seg| seg[:start]}
	end

	def clean_files
	end

	def compute_start(segment, file_number)
		((segment.start.to_f + (file_number.to_f * AUDIO_CHUNK_LENGTH)) * @skew).to_i
	end


end

AudioDiarize.new('/home/zerofries/Music/podcast_sample2.wav').process