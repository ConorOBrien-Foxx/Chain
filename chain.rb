# chain

require 'optparse'

$encoding = "iso-8859-1"

def read_file(file_name, my_encoding = $encoding)
    prog = File.read(
        file_name, :encoding => my_encoding
    ).chars
    if my_encoding.upcase == "UTF-8"
        # map chars to thingies
        iso_like_chars = "\xA0¡¢£¤¥¦§¨©ª«¬­®¯°±²³´µ¶·¸¹º»¼½¾¿ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞßàáâãäåæçèéêëìíîïðñòóôõö÷øùúûüýþÿ"
        prog.map! { |chr|
            if iso_like_chars.include? chr
                (160 + iso_like_chars.index(chr)).chr
            else
                chr
            end
        }
    end
    prog.map! { |e| e.force_encoding "UTF-8" }
    prog
end

class String
    def ord
        val = self[0].unpack("c*")[0]
        val += 256 if val < 0
        val
    end
end

class TrueClass;  def to_i; return 1; end; end;
class FalseClass; def to_i; return 0; end; end;

class ChainCommand
    @@opts_default = {
        :use_stack => true,
        :consume => true,
    }
    
    def initialize(name, func, opts = {})
        @name = name
        @func = func
        @arity = func.arity
        @opts = @@opts_default.merge(opts)
    end
    
    attr_accessor :name, :func, :arity
    
    def [](inst)
        if @opts[:use_stack]
            args = inst.obtain @arity
            inst.stack.push *args unless @opts[:consume]
            res = @func[*args]
            inst.stack.push res unless res == nil
        else
            @func[inst]
        end
    end
    
    def inspect
        "#<ChainCommand `#{@name.inspect}`>"
    end
end

def input
    STDIN.gets.chomp
end

class ANY
    def ANY.===(other)
        true
    end
end

class Typed
    def initialize(hash)
        @hash = hash
        @arity = hash.to_a.first.size
    end
    
    attr_accessor :hash, :arity
    
    def match(args)
        @hash.map { |type_arr, val|
            # p [type_arr, val, args]
            type_arr.zip(args).all? { |arr|
                type, arg = arr
                # p [type, arg, arr]
                type === arr
            } ? val : nil
        }.reject { |e| e == nil } .first
    end
    
    def [](*args)
        proc = match(args)
        # p proc
        proc[*args]
    end
end
# e.g
#
#   Typed.new({
#       [String, String] => -> a, b { a + b }
#   })

class Chain
    @@commands = [
        ChainCommand.new("\xA2", -> a { a.to_i }),
        ChainCommand.new("\xA3", -> a { "1" * a.to_i }),
        ChainCommand.new("\xA4", -> inst {
            inst.stack.push inst.stack[-1]
        }, { :use_stack => false }),
        ChainCommand.new("\xA6", -> a, b { (Regexp.new(b) === a).to_i }),
        ChainCommand.new("\xAC", -> a { 1 - a }),
        ChainCommand.new("\xB0", -> a, b { a * b.ord }),
        ChainCommand.new("\xB1", -> a, b { a + b }),
        ChainCommand.new("\xB6", Typed.new({
            [String]  => -> a { a + "\n" },
            [Numeric] => -> a { a },
        })),
        ChainCommand.new("\xBA", -> { }),
        ChainCommand.new("\xCC", -> { input }),
        ChainCommand.new("\xCD", -> { input.to_i }),
        ChainCommand.new("\xCE", -> { input.ord }),
        ChainCommand.new("\xD2", -> a { print a }),
        ChainCommand.new("\xD3", -> a { puts a }),
        ChainCommand.new("\xD4", -> inst {
            inst.opts[:handle_default_current] =
                inst.opts[:handle_default_current] == :handle_default_primary ?
                    :handle_default_secondary :
                    :handle_default_primary
        }, { :use_stack => false }),
        ChainCommand.new("\xD7", -> inst {
            inst.index += 1
            cmd_to_rep = inst.cur
            amount_to_rep = inst.stack.pop
            if inst.commands.has_key? cmd_to_rep
                amount_to_rep.times {
                    inst.commands[cmd_to_rep][inst]
                }
            else
                inst.stack.push cmd_to_rep * amount_to_rep
            end
            nil
        }, { :use_stack => false }),
        ChainCommand.new("\xF2", -> a { print a }, { :consume => false }),
        ChainCommand.new("\xF3", -> a { puts a },  { :consume => false }),
        ChainCommand.new("\xFE", -> inst {
            amount_to_rep = inst.stack.pop
            rest_of_prog = inst.prog[inst.index+1..-1]
            amount_to_rep.times { Chain.execute(rest_of_prog) }
        }, { :use_stack => false }),
        *(128...144).map.with_index { |c, i|
            ChainCommand.new(c.chr.force_encoding("UTF-8"), -> { i })
        }]
    
    @@commands = @@commands.map { |e| [e.name, e] }.to_h
    
    @@opts_default = {
        :handle_default_primary     => -> chr, inst { inst.build += chr },
        :handle_default_secondary   => -> chr, inst { print chr },
        :handle_default_current     => :handle_default_primary,
    }
    
    def Chain.falsey(val)
        return val == "" || val == 0
    end
    
    def Chain.truthy(val)
        return !Chain.falsey(val)
    end
    
    def obtain(num)
        while @stack.size < num
            @stack.unshift input
        end
        @stack.pop num
    end
    
    def initialize(program, opts = {})
        @commands = @@commands
        @running = true
        @prog = program
        @index = 0
        @stack = []
        @opts = @@opts_default.merge(opts)
        @build = ""
        
        # fill unmatched `«`s
        loop do
            # calculate depth
            i = 0
            depth = 0
            while i < @prog.size
                depth += 1 if prog[i] == "\xAB"
                depth -= 1 if prog[i] == "\xBB"
                i += 1
            end
            break               if depth == 0
            prog.unshift "\xAB" if depth < 0
            prog.push    "\xBB" if depth > 0
        end
    end
    
    def handle_default(chr)
        @opts[@opts[:handle_default_current]][chr, self]
    end
    
    attr_accessor :index, :prog, :commands, :stack, :opts, :build
    
    def cur
        @prog[@index]
    end
    
    def step
        if @index >= @prog.size
            if @build.size > 0
                @stack.push @build
                @build = ""
            end
            @running = false
            return @running
        end
        
        if @commands.has_key?(cur) || ["\xA1", "\xAB", "\xBB"].include?(cur)
            if @build.size > 0
                @stack.push @build
                @build = ""
            end
        else
            handle_default cur
        end
        
        if @commands.has_key? cur
            @commands[cur][self]
        elsif cur == "\xA1"
            @index += 1
            handle_default cur
        elsif cur == "\xAB"
            
        elsif cur == "\xBB"
            if Chain.truthy @stack.last
                depth = 1
                @index -= 1
                loop do
                    depth -= 1 if cur == "\xAB"
                    depth += 1 if cur == "\xBB"
                    break if depth == 0 || @index < 0
                    @index -= 1
                end
            end
        else
            unhandled = true
        end
        
        @index += 1
    end
    
    def run
        step while @running
    end
    
    def Chain.execute(prog)
        $outted = false
        def print(*a)
            $stdout.print(*a)
            $outted = true
            nil
        end
        def puts(*a)
            a.map { |e|
                print e
                print "\n"
            }
            nil
        end
        def p(*a)
            puts *a.map(&:inspect)
            nil
        end
        inst = Chain.new prog
        inst.run
        puts inst.stack.join unless $outted
    end
end

# activate interpreter
if __FILE__ == $0
    options = {
        :utf8 => false
    }
    OptionParser.new { |opts|
        opts.banner = "Usage: chain.rb [options]"
        opts.separator ""
        opts.separator "[options]"
        opts.on("-u", "--utf8", "Read a unicode file instead of an ISO-8859-1 file.") { |v|
            options[:utf8] = v
        }
        opts.on_tail("-h", "--help", "-?", "Show the help message") {
            puts opts
        }
    }.parse!
    
    # p options
    # p ARGV
    
    # exit
    
    file_name = ARGV[0]
    if options[:utf8]
        prog = read_file file_name, "UTF-8"
    else
        prog = read_file file_name
    end
    Chain.execute prog
    unless $stdin.tty?
        rest_of_stdin = $stdin.read
        print rest_of_stdin if rest_of_stdin.size > 0
    end
end