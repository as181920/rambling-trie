require 'fileutils'
require 'benchmark'

namespace :performance do
  def report name, trie, output
    words = %w(hi help beautiful impressionism anthropological)
    methods = [:word?, :partial_word?]

    output.puts "==> #{name}"
    methods.each do |method|
      output.puts "`#{method}`:"
      words.each do |word|
        output.print "#{word} - #{trie.send method, word}".ljust 30
        output.puts Benchmark.measure { 200_000.times { trie.send method, word }}
      end
    end
  end

  def generate_report filename = nil
    output = filename.nil? ? $stdout : File.open(filename, 'a+')

    output.puts "\nReport for rambling-trie version #{Rambling::Trie::VERSION}"

    trie = nil
    measure = Benchmark.measure { trie = Rambling::Trie.create path('assets', 'dictionaries', 'words_with_friends.txt') }

    if ENV['profile_creation']
      output.puts '==> Creation'
      output.print 'Rambling::Trie.create'.ljust 30
      output.puts measure
    end

    report 'Uncompressed', trie, output

    return unless trie.respond_to? :compress!

    trie.compress!
    report 'Compressed', trie, output

    output.close
  end

  def path *filename
    File.join File.dirname(__FILE__), '..', '..', '..', '..', *filename
  end

  def with_gc_stats &block
    puts "Live objects before - #{GC.stat[:heap_live_slots]}"
    block.call
    puts "Live objects after  - #{GC.stat[:heap_live_slots]}"
  end

  desc 'Generate performance report'
  task :report do
    puts 'Generating performance report...'
    generate_report
  end

  namespace :report do
    desc 'Generate performance report and append result to reports/performance'
    task :save do
      puts 'Generating performance report...'
      generate_report path('reports', 'performance')
      puts 'Report has been saved to reports/performance'
    end
  end

  namespace :profile do
    desc 'Generate application profiling reports'
    task :call_tree do
      require 'ruby-prof'

      puts 'Generating call tree profiling reports...'

      trie = Rambling::Trie.create path('assets', 'dictionaries', 'words_with_friends.txt')
      words = %w(hi help beautiful impressionism anthropological)
      methods = [:word?, :partial_word?]
      tries = [lambda {trie.clone}, lambda {trie.clone.compress!}]
      time = Time.now.to_i

      methods.each do |method|
        tries.each do |trie_generator|
          trie = trie_generator.call
          result = RubyProf.profile merge_fibers: true do
            words.each do |word|
              200_000.times { trie.send method, word }
            end
          end

          path = path('reports', "profile-#{trie.compressed? ? 'compressed' : 'uncompressed'}-#{method.to_s.sub(/\?/, '')}-#{time}")

          FileUtils.mkdir_p path
          printer = RubyProf::CallTreePrinter.new(result)
          printer.print path: path
        end
      end

      puts 'Done'
    end

    desc 'Generate memory profiling report'
    task :memory do
      require 'memory_profiler'

      puts 'Generating memory profiling reports...'

      trie = nil
      dictionary = path 'assets', 'dictionaries', 'words_with_friends.txt'
      time = Time.now.to_i

      puts
      puts 'memory-profile-new-trie'
      MemoryProfiler.report do
        with_gc_stats { trie = Rambling::Trie.create dictionary }
      end.pretty_print to_file: path('reports', "#{time}-memory-profile-new-trie")

      puts
      puts 'memory-profile-compressed-trie'
      MemoryProfiler.report do
        with_gc_stats { trie.compress! }
      end.pretty_print to_file: path('reports', "#{time}-memory-profile-compressed-trie")

      puts
      puts 'memory-profile-trie-and-compress'
      MemoryProfiler.report do
        with_gc_stats { trie = Rambling::Trie.create dictionary }
        with_gc_stats { trie.compress! }
      end.pretty_print to_file: path('reports', "#{time}-memory-profile-trie")

      puts
      puts 'memory-profile-trie-gc'
      MemoryProfiler.report do
        with_gc_stats { trie = Rambling::Trie.create dictionary }
        with_gc_stats { trie.compress! }
        with_gc_stats { GC.start }
      end.pretty_print to_file: path('reports', "#{time}-memory-profile-trie-gc")

      puts 'End'
    end
  end

  desc 'Generate profiling and performance reports'
  task all: ['profile:call_tree', :report]
end
