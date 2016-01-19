require "unindent"

describe "CLI" do
  before :all do
    # use local scripts
    ENV["PATH"] = "#{File.join(File.dirname(__FILE__),"..","bin")}:#{ENV["PATH"]}"
  end

  def run(command, options={})
    output = `#{command}`
    return output if $?.success?
    return output if options[:fail]

    message = "Unable to run #{command.inspect} in #{Dir.pwd}.\n#{output}"
    warn "ERROR: #{message}"
    raise message
  end

  def write(file, content)
    File.open(file, 'w'){|f| f.write content }
  end

  around do |example|
    dir = "spec/tmp"
    run "rm -rf #{dir}"
    run "mkdir #{dir}"

    # use fake home for .ssh hacks
    run "mkdir #{dir}/home"
    ENV["HOME"] = File.absolute_path("#{dir}/home")

    Dir.chdir dir do
      run "touch a"
      run "git init"
      run "git add ."
      run "git config user.email 'rspec-tests@example.com'"
      run "git config user.name 'rspec test suite'"
      run "git commit -am 'initial'"
      run "git config --unset user.email"
      run "git config --unset user.name"
      example.run
    end
  end

  describe "about" do
    it "lists the user" do
      run "git config user.name NAME"
      run("git about").should =~ /git user:\s+NAME/
    end

    it "lists the user as NONE if there is none" do
      run "git config user.name ''"
      run("git about").should =~ /git user:\s+NONE/
    end

    it "lists the email" do
      run "git config user.email EMAIL"
      run("git about").should =~ /git email:\s+EMAIL/
    end

    it "lists the email as NONE if there is none" do
      run "git config user.email ''"
      run("git about").should =~ /git email:\s+NONE/
    end

    it "does not find a project" do
      run("git about").should =~ /GitHub project:\s+NONE/
    end

    context "with github project" do
      before do
        run "mkdir home/.ssh"
        run "touch home/.ssh/id_github_foo"
        run "ln -s home/.ssh/id_github_foo home/.ssh/id_github_current"
      end

      it "finds a project" do
        run("git about").should =~ /GitHub project:\s+foo/
      end
    end
  end

  describe "collab" do
    def expect_config(result, name, initials, email, options={})
      global = "cd /tmp && " if options[:global]
      run("#{global}git config user.name").should == "#{name}\n"
      run("#{global}git config user.initials").should == "#{initials}\n"
      run("#{global}git config user.email").should == "#{email}\n"

      prefix = (options[:global] ? "global: " : "local:  ")
      result.should include "#{prefix}user.name #{name}"
      result.should include "#{prefix}user.initials #{initials}"
      result.should include "#{prefix}user.email #{email}"
    end

    def git_config_value(name, global = false)
      global_prefix = "cd /tmp && " if global
      `#{global_prefix}git config user.#{name}`
    end

    it "prints help" do
      result = run "git-collab --help"
      result.should include("Configures git authors when collab programming")
    end

    it "prints version" do
      result = run "git collab --version"
      result.should =~ /\d+\.\d+\.\d+/
    end

    context "with .collabs file" do
      before do
        write ".collabs", <<-YAML.unindent
          collabs:
            ab: Aa Bb
            bc: Bb Cc
            cd: Cc Dd

          email:
            prefix: the-collab
            domain: the-host.com
          YAML
      end

      describe "global" do
        it "sets collabs globally when global: true is set" do
          write ".collabs", File.read(".collabs") + "\nglobal: true"
          result = run "git collab ab"
          expect_config result, "Aa Bb", "ab", "the-collab+aa@the-host.com", :global => true
        end

        it "sets collabs globally when --global is given" do
          result = run "git collab ab --global"
          result.should include "global: user.name Aa Bb"
          expect_config result, "Aa Bb", "ab", "the-collab+aa@the-host.com", :global => true
        end

        it "unsets global config when no argument is passed" do
          run "git collab ab --global"
          run "git collab ab"
          result = run "git collab --global"
          #result.should include "Unset --global user.name, user.email and user.initials"
          expect_config result, "Aa Bb", "ab", "the-collab+aa@the-host.com"
          result.should_not include("global:")
        end
      end

      it "can set a single user as collab" do
        result = run "git collab ab"
        expect_config result, "Aa Bb", "ab", "the-collab+aa@the-host.com"
      end

      it "can set a 2 users as collab" do
        result = run "git collab ab bc"
        expect_config result, "Aa Bb and Bb Cc", "ab bc", "the-collab+aa+bb@the-host.com"
      end

      it "can set n users as collab" do
        result = run "git collab ab bc cd"
        expect_config result, "Aa Bb, Bb Cc and Cc Dd", "ab bc cd", "the-collab+aa+bb+cc@the-host.com"
      end

      it "prints names, email addresses, and initials in alphabetical order" do
        result = run "git collab ab cd bc"
        expect_config result, "Aa Bb, Bb Cc and Cc Dd", "ab bc cd", "the-collab+aa+bb+cc@the-host.com"
      end

      it "can set a user with apostrophes as collab" do
        write ".collabs", File.read(".collabs").sub("Aa Bb", "Pete O'Connor")
        result = run "git collab ab"
        expect_config result, "Pete O'Connor", "ab", "the-collab+pete@the-host.com"
      end

      it "fails when there is no .git in the tree" do
        run "rm -f /tmp/collabs"
        run "cp .collabs /tmp"
        Dir.chdir "/tmp" do
          result = run "git collab ab 2>&1", :fail => true
          result.should include("Not a git repository (or any of the parent directories)")
        end
        run "rm -f /tmp/collabs"
      end

      it "finds .collabs file in lower parent folder" do
        run "mkdir foo"
        Dir.chdir "foo" do
          result = run "git collab ab"
          expect_config result, "Aa Bb", "ab", "the-collab+aa@the-host.com"
        end
      end

      it "unsets local config when no argument is passed" do
        run "git collab ab --global"
        run "git collab bc"
        result = run "git collab"
        result.should include "Unset user.name, user.email, user.initials"
        expect_config result, "Aa Bb", "ab", "the-collab+aa@the-host.com", :global => true
        result.should_not include("local:")
      end

      it "uses hard email when given" do
        write ".collabs", File.read(".collabs").sub(/email:.*/m, "email: foo@bar.com")
        result = run "git collab ab"
        expect_config result, "Aa Bb", "ab", "foo@bar.com"
      end

      context "when no email config is present" do
        before do
          write ".collabs", File.read(".collabs").sub(/email:.*/m, "")
        end

        it "doesn't set email" do
          run "git collab ab"
          git_config_value('email').should be_empty
        end

        it "doesn't report about email" do
          result = run "git collab ab"
          result.should_not include "email"
        end
      end

      it "uses no email prefix when only host is given" do
        write ".collabs", File.read(".collabs").sub(/email:.*/m, "email:\n  domain: foo.com")
        result = run "git collab ab"
        expect_config result, "Aa Bb", "ab", "aa@foo.com"
      end

      context "when no no_solo_prefix is given" do
        before do
          write ".collabs", File.read(".collabs").sub(/email:.*/m, "email:\n  prefix: collabs\n  no_solo_prefix: true\n  domain: foo.com")
        end

        it "uses no email prefix for single developers" do
          result = run "git collab ab"
          expect_config result, "Aa Bb", "ab", "aa@foo.com"
        end

        it "uses email prefix for multiple developers" do
          result = run "git collab ab bc"
          expect_config result, "Aa Bb and Bb Cc", "ab bc", "collabs+aa+bb@foo.com"
        end
      end

      it "fails with unknown initials" do
        result = run "git collab xx", :fail => true
        result.should include("Couldn't find author name for initials: xx")
      end

      it "uses alternate email prefix" do
        write ".collabs", File.read(".collabs").sub(/ab:.*/, "ab: Aa Bb; blob")
        result = run "git collab ab"
        expect_config result, "Aa Bb", "ab", "the-collab+blob@the-host.com"
      end
    end

    context "without a .collabs file in the tree" do
      around do |example|
        Dir.chdir "/tmp" do
          run "rm -f .collabs"
          dir = "git_stats_test"
          run "rm -rf #{dir}"
          run "mkdir #{dir}"
          Dir.chdir dir do
            run "git init"
            example.run
          end
          run "rm -rf #{dir}"
        end
      end

      context "and without a .collabs file in the home directory" do
        it "fails if it cannot find a collabs file" do
          run "git collab ab", :fail => true
        end

        it "prints instructions" do
          result = run "git collab ab", :fail => true
          result.should include("Could not find a .collabs file. Create a YAML file in your project or home directory.")
        end
      end

      context "but a .collabs file in the home directory" do
        around do |example|
          file = File.join(ENV["HOME"], ".collabs")
          write file, <<-YAML.unindent
            collabs:
              ab: Aa Bb
              bc: Bb Cc
              cd: Cc Dd

            email:
              prefix: the-collab
              domain: the-host.com
          YAML

          example.run

          FileUtils.rm file
        end

        it "loads the file" do
          result = run "git collab ab"
          expect_config result, "Aa Bb", "ab", "the-collab+aa@the-host.com"
        end
      end
    end
  end

  describe 'collab-commit' do
    before do
      write ".collabs", <<-YAML.unindent
          collabs:
            ab: Aa Bb; abb
            bc: Bb Cc; bcc
            cd: Cc Dd; cdd

          email:
            prefix: the-collab
            domain: the-host.com

          email_addresses:
            bc: test@other-host.com
      YAML
    end

    context 'when a collab has been set' do
      before do
        run "git collab ab cd"
      end

      def author_name_of_last_commit
        (run "git log -1 --pretty=%an").strip
      end

      def author_email_of_last_commit
        (run "git log -1 --pretty=%ae").strip
      end

      def committer_name_of_last_commit
        (run "git log -1 --pretty=%cn").strip
      end

      def committer_email_of_last_commit
        (run "git log -1 --pretty=%ce").strip
      end

      it "makes a commit" do
        git_collab_commit
        output = run "git log -1"
        output.should include("Collab pare pear")
      end

      it "sets the author name to the collab's names" do
        git_collab_commit
        output = run "git log -1 --pretty=%an"
        output.strip.should eq("Aa Bb and Cc Dd")
      end

      it "randomly chooses from collab and sets user.email" do
        emails = 6.times.map do
          git_collab_commit
          author_email_of_last_commit
        end.uniq
        emails.should =~ ['abb@the-host.com', 'cdd@the-host.com']
      end

      context 'when git options are passed' do
        it 'forwards those options to git' do
          git_collab_commit
          run 'git collab ab bc'
          run 'git collab-commit --amend -C HEAD --reset-author'

          output = run "git log -1 --pretty=%an"
          output.strip.should eq("Aa Bb and Bb Cc")
        end
      end

      context 'when the collab is set globally and the local repo has custom user name and email' do
        before do
          run 'git collab --global ab cd'
          run "git config user.name 'Betty White'"
          run "git config user.email 'betty@example.com'"
        end

        it 'still makes the commit with the correct user name' do
          git_collab_commit

          author_name_of_last_commit.should eq("Aa Bb and Cc Dd")
        end

        it 'still makes the commit with the correct user email' do
          git_collab_commit

          %w(abb@the-host.com cdd@the-host.com).should include(author_email_of_last_commit)
        end

        it 'still makes the commit with the correct committer name' do
          git_collab_commit

          committer_name_of_last_commit.should eq("Aa Bb and Cc Dd")
        end

        it 'still makes the commit with the correct committer email' do
          git_collab_commit

          %w(abb@the-host.com cdd@the-host.com).should include(committer_email_of_last_commit)
        end
      end

      context 'when one of the collab has a custom email address' do
        before do
          run 'git collab ab bc'
        end

        it 'uses that email address' do
          emails = 6.times.map do
            git_collab_commit
            author_email_of_last_commit
          end.uniq
          emails.should =~ ['abb@the-host.com', 'test@other-host.com']
        end
      end
    end

    context 'when no collab has been set' do
      it 'raises an exception' do
        git_collab_commit.should include('Error: No collab set')
      end
    end

    context 'when -h flag is passed' do
      it 'shows the help message' do
        results = run 'git collab-commit -h'
        results.gsub(/\s+/, ' ').should include('randomly chooses the author email from the members of the collab')
      end
    end

    def git_collab_commit
      run "echo #{rand(100)} > b"
      run 'git add b'
      run 'git collab-commit -m "Collab pare pear"', :fail => true
    end
  end
end
