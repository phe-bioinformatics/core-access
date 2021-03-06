@@test_dir = File.dirname(__FILE__)
require 'helper'
require 'stringio'
require 'fileutils'
require 'bioutils/rich_sequence_utils'
require "#{@@test_dir}/../lib/core-access" # require lib/core-access so changes are picked up without rake install
include ClusterCreate
include ClusterAnnotate
include ClusterSearch
include ClusterOutput

class TestCoreAccess < Test::Unit::TestCase
  @@clustering_cutoffs = [99,98,95,90,85]
  def teardown
    ActiveRecord::Base.remove_connection
  end
  context "core-access test" do

    should "find the sequence file list file" do
      assert File.exists?("#{@@test_dir}/fasta_sequence_file_list.txt")
    end
    should "find all files in sequence list" do
      file_exists_array = Array.new
      File.read("#{@@test_dir}/fasta_sequence_file_list.txt").split("\n").map{|line| line.split("\t").first}.each do |file|
        file_exists_array << File.exists?("#{@@test_dir}/#{file}")
      end
      assert_equal(false, file_exists_array.include?(false))
    end
    should "find the reference file" do
      assert File.exists?("#{@@test_dir}/test_data/ref.gbk")
    end
  end

  context "core-access methods" do
    should "find the correct strain names when supplied" do
      sequence_files, strain_names = extract_file_and_strain_names_from_file_list(:sequence_file_list => "#{@@test_dir}/fasta_sequence_file_list.txt")
      assert_equal ["strain1", "strain2"], strain_names
    end
    should "create a multi fasta file from the input files" do
      FileUtils.rm("/tmp/ref_glimmer.icm", :force => true)
      FileUtils.rm("/tmp/cds_proteins.fas", :force => true)
      sequence_files, strain_names = extract_file_and_strain_names_from_file_list(:sequence_file_list => "#{@@test_dir}/fasta_sequence_file_list.txt")
      sequence_files.map!{|sf| "#{@@test_dir}/#{sf}"}
      silence do
        create_cds_multi_fasta_file(:training_sequence_path => "#{@@test_dir}/test_data/ref.gbk", :root_folder  => "/tmp", :cds_multi_fasta_file => "/tmp/cds_proteins.fas", :sequence_files => sequence_files)
      end
      assert File.exists?("/tmp/cds_proteins.fas")
    end
    should "create cd-hit output from a multifasta file" do
      FileUtils.rm("/tmp/cdhit_clusters*", :force => true)
      silence do
        make_heirachical_clusters(:root_folder  => "/tmp", :cds_multi_fasta_file => "#{@@test_dir}/test_data/cds_proteins.fas", :clustering_cutoffs => @@clustering_cutoffs, :cdhit_dir => "/usr/local/cdhit")
      end
      assert File.exists?("/tmp/cdhit_clusters-85")
    end
    should "create a cluster database from cd-hit output" do
      FileUtils.rm("/tmp/test.sqlite", :force => true)
      sequence_files, strain_names = extract_file_and_strain_names_from_file_list(:sequence_file_list => "#{@@test_dir}/fasta_sequence_file_list.txt")
      @@clustering_cutoffs.each do |clustering_cutoff|
        FileUtils.cp("#{@@test_dir}/test_data/cdhit_clusters-#{clustering_cutoff}.clstr", "/tmp/")
      end
      # create database
      silence do
        make_db_clusters(:root_folder => "/tmp", :db_location => "/tmp/test.sqlite", :clustering_cutoffs => @@clustering_cutoffs, :strain_names => strain_names)
      end
      assert_equal 1, Cluster.where(:id => 1).first.genes.size
      assert_equal 2, Cluster.where(:id => Cluster.count).first.genes.size
    end

    should "create representatives in clusters" do
      FileUtils.rm("/tmp/test.sqlite", :force => true)
      FileUtils.cp("#{@@test_dir}/test_data/test_without_representatives.sqlite", "/tmp/test.sqlite")
      # add represenatives to clusters
      sequence_files, strain_names = extract_file_and_strain_names_from_file_list(:sequence_file_list => "#{@@test_dir}/genbank_sequence_file_list.txt")
      sequence_files.map!{|sf| "#{@@test_dir}/#{sf}"}
      silence do
        add_representative_sequences_to_cluster(:root_folder => "/tmp", :db_location => "/tmp/test.sqlite", :sequence_files => sequence_files, :strain_names => strain_names)
      end
      assert_equal @@representative_of_cluster1_sequence, Cluster.where(:id => 1).first.representative.sequence
      assert_equal @@representative_of_cluster2_sequence, Cluster.where(:id => Cluster.count).first.representative.sequence
    end

    should "make super clusters" do
      FileUtils.rm("/tmp/test.sqlite", :force => true)
      FileUtils.cp("#{@@test_dir}/test_data/test_with_representatives.sqlite", "/tmp/test.sqlite")
      # add represenatives to clusters
      silence do
        make_super_clusters(:cdhit_dir => "/usr/local/cdhit", :cutoff => 65, :db_location => "/tmp/test.sqlite")
      end
      assert_equal true, Cluster.where(:id => Cluster.count).first.is_parent_cluster
      assert_equal 65, Cluster.where(:id => Cluster.count).first.cutoff
      assert_equal 2, Cluster.where(:id => Cluster.count).first.number_of_members
      assert_equal 1, Cluster.where(:id => Cluster.count).first.number_of_strains
    end

    should "find correct number of core genes" do
      FileUtils.rm("/tmp/test.sqlite", :force => true)
      FileUtils.cp("#{@@test_dir}/test_data/test_with_superclusters.sqlite", "/tmp/test.sqlite")
      # find core genes
      core_clusters = find_core_clusters(:db_location => "/tmp/test.sqlite")
      assert_equal 326, core_clusters.size
    end

    should "find correct number of unique genes" do
      FileUtils.rm("/tmp/test.sqlite", :force => true)
      FileUtils.cp("#{@@test_dir}/test_data/test_with_superclusters.sqlite", "/tmp/test.sqlite")
      # find shared genes
      unique_clusters = find_unique_clusters(:db_location => "/tmp/test.sqlite", :strain_names => ["strain1"])
      assert_equal 62, unique_clusters.size
    end

    should "find correct number of partially shared genes" do
      FileUtils.rm("/tmp/test.sqlite", :force => true)
      FileUtils.cp("#{@@test_dir}/test_data/test_with_superclusters.sqlite", "/tmp/test.sqlite")
      # find shared genes
      unique_clusters = find_partial_shared_clusters(:db_location => "/tmp/test.sqlite", :strain_names => ["strain1"])
      assert_equal 62, unique_clusters.size
    end

    should "annotate clusters" do
      FileUtils.rm("/tmp/test.sqlite", :force => true)
      FileUtils.cp("#{@@test_dir}/test_data/test_with_superclusters.sqlite", "/tmp/test.sqlite")
      require 'core-access/cluster_database'
      extend ClusterDB
      require 'core-access/cluster_models'
      make_db_connection("/tmp/test.sqlite")
      assert Annotation.all.size == 0
      silence do
        annotate_clusters(
          :db_location => "/tmp/test.sqlite",
          :root_folder => "/tmp",
          :blast_dir => "/usr/local/blast/bin",
          :fastacmd_dir => "/usr/local/blast/bin",
          :reference_genomes => ["#{@@test_dir}/test_data/ref_seq1.gbk","#{@@test_dir}/test_data/ref_seq2.gbk" ],
          :reference_blast_program => "blastn",
          :reference_percent_identity_cutoff => 90,
          :reference_minimum_hit_length => 85,
          :local_blast_db => "/Volumes/DataRAID/blast_databases/microbial_genomes",
          :local_db_blast_program => "blastn",
          :local_db_percent_identity_cutoff => 80,
          :local_db_minimum_hit_length => 80,
          :ncbi_blast_program => "blastp",
          :ncbi_percent_identity_cutoff => 80,
          :ncbi_minimum_hit_length => 80,
          :annotate_vs_local_db => true,
          :annotate_by_remote_blast => false,
          :accept_reciprocal_hits_with_multiple_hits_incl_query  => true,
          :accept_first_reciprocal_hit_containing_query => false,
          :parallel_processors => 6)
      end
      assert Annotation.all.size > 1
    end

    should "output gene presence absence data with core genes" do
      FileUtils.rm("/tmp/test.sqlite", :force => true)
      FileUtils.rm("/tmp/gene_presence_absence.txt", :force => true)
      FileUtils.cp("#{@@test_dir}/test_data/test_with_annotations.sqlite", "/tmp/test.sqlite")
      silence do
        output_gene_presence_absence(
          :db_location =>  "/tmp/test.sqlite",
          :output_filepath => "/tmp/gene_presence_absence.txt",
          :without_core_genes => false)
      end
      last_two_lines = `tail -n 2 /tmp/gene_presence_absence.txt`.split("\n")
      assert_equal "414: hypothetical protein\t0\t1", last_two_lines.first
      assert_equal "415: hypothetical protein\t1\t1", last_two_lines.last
      assert_equal 416, `wc -l /tmp/gene_presence_absence.txt`.split.first.to_i
    end

    should "output gene presence absence data without core genes" do
      FileUtils.rm("/tmp/test.sqlite", :force => true)
      FileUtils.rm("/tmp/gene_presence_absence.txt", :force => true)
      FileUtils.cp("#{@@test_dir}/test_data/test_with_annotations.sqlite", "/tmp/test.sqlite")
      silence do
        output_gene_presence_absence(
          :db_location =>  "/tmp/test.sqlite",
          :output_filepath => "/tmp/gene_presence_absence.txt",
          :without_core_genes => true)
      end
      last_two_lines = `tail -n 2 /tmp/gene_presence_absence.txt`.split("\n")
      assert_equal "412: hypothetical protein\t1\t0", last_two_lines.first
      assert_equal "414: hypothetical protein\t0\t1", last_two_lines.last
      assert_equal 90, `wc -l /tmp/gene_presence_absence.txt`.split.first.to_i
    end

  end

  context "core-access" do
    should "print out read me file" do
      output = `#{@@test_dir}/../bin/core-access readme`
      assert output =~ /Core Access ReadMe\n==================/
    end
    should "be able to read in a config file in YAML format" do
      output = `#{@@test_dir}/../bin/core-access create -db test.sqlite3 -cf #{@@test_dir}/config_file.yml`
      assert output =~ /"clustering_cutoffs"=>"99-98-97-96-95-94-93-92-91-90-85"/
    end
    should "fail to find glimmer3 when not specifying a glimmer path" do
      output = `#{@@test_dir}/../bin/core-access create -db test.sqlite3 -od /tmp -fl #{@@test_dir}/fasta_sequence_file_list.txt -fd #{@@test_dir} 2>&1`
      assert output =~ /glimmer3 must be in your PATH/
    end

    should "succeed to find glimmer3 when not specifying a glimmer path but it's in the PATH" do
      ENV['PATH'] = ENV['PATH'] +  ":/usr/local/glimmer/bin"
      output = `#{@@test_dir}/../bin/core-access create -db test.sqlite3 -od /tmp -fl #{@@test_dir}/fasta_sequence_file_list.txt -fd #{@@test_dir} 2>&1`
      assert output =~ /Can not find cd-hit/
    end

    should "fail to find glimmer3 in /tmp" do
      output = `#{@@test_dir}/../bin/core-access create -db test.sqlite3 -od /tmp -fl #{@@test_dir}/fasta_sequence_file_list.txt -fd #{@@test_dir} -gd /tmp 2>&1`
      assert output =~ /Can not find glimmer3/
    end
    should "fail to find cd-hit on /tmp" do
      output = `#{@@test_dir}/../bin/core-access create -db test.sqlite3 -od /tmp -fl #{@@test_dir}/genbank_sequence_file_list.txt -gd /usr/local/glimmer -fd #{@@test_dir} -cd /tmp 2>&1`
      assert output =~ /Can not find cd-hit/
    end
    should "create a multiple fasta file, run cd-hit and make a database when specifying the create command and correct options" do
      FileUtils.rm("/tmp/ref_glimmer.icm", :force => true)
      FileUtils.rm("/tmp/cds_proteins.fas", :force => true)
      FileUtils.rm("/tmp/cdhit_clusters*", :force => true)
      FileUtils.rm("/tmp/test.sqlite", :force => true)
      output = `#{@@test_dir}/../bin/core-access create -db test.sqlite -fl #{@@test_dir}/fasta_sequence_file_list.txt -fd #{@@test_dir} -gd /usr/local/glimmer -ts #{@@test_dir}/test_data/ref.gbk -cd /usr/local/cdhit -od /tmp -sc 65 2>&1`
      # check that the multi fasta file creation worked
      assert File.exists?("/tmp/cds_proteins.fas")
      # check that cd-hit ran OK
      assert File.exists?("/tmp/cdhit_clusters-85")
      # check that database was created with correct values
      assert File.exists?("/tmp/test.sqlite")
      require 'core-access/cluster_database'
      extend ClusterDB
      require 'core-access/cluster_models'
      make_db_connection("/tmp/test.sqlite")

      assert_equal 1, Cluster.where(:id => 1).first.genes.size
      # :id => Cluster.where(:is_parent_cluster => false).count is way of finding last non parent cluster
      assert_equal 2, Cluster.where(:id => Cluster.where(:is_parent_cluster => false).count).first.genes.size
      # check representatives are in the db
      assert_equal @@representative_of_cluster1_sequence, Cluster.where(:id => 1).first.representative.sequence
      # :id => Cluster.where(:is_parent_cluster => false).count is way of finding last non parent cluster
      assert_equal @@representative_of_cluster2_sequence, Cluster.where(:id => Cluster.where(:is_parent_cluster => false).count).first.representative.sequence
      # check super clusters are in database, Cluster.where(:id => Cluster.count) is way of finding last cluster
      assert_equal true, Cluster.where(:id => Cluster.count).first.is_parent_cluster
      assert_equal 65, Cluster.where(:id => Cluster.count).first.cutoff
      assert_equal 2, Cluster.where(:id => Cluster.count).first.number_of_members
      assert_equal 1, Cluster.where(:id => Cluster.count).first.number_of_strains
    end
    should "find correct number of core genes" do
      FileUtils.rm("/tmp/test.sqlite", :force => true)
      FileUtils.cp("#{@@test_dir}/test_data/test_with_superclusters.sqlite", "/tmp/test.sqlite")
      output = `#{@@test_dir}/../bin/core-access search -cg -db /tmp/test.sqlite`
      assert_equal 327, output.split("\n").size # number of core genes = 326 + 1 header line
      assert_equal "415\t85\tfalse\t2\t2\tstrain1\tstrain2", output.split("\n").last
    end

    should "find correct number of unique genes" do
      FileUtils.rm("/tmp/test.sqlite", :force => true)
      FileUtils.cp("#{@@test_dir}/test_data/test_with_superclusters.sqlite", "/tmp/test.sqlite")
      # find shared genes
      output = `#{@@test_dir}/../bin/core-access search -ug -sn strain1 -db /tmp/test.sqlite`
      assert_equal 63, output.split("\n").size
    end

    should "output all presence and absence data" do
      FileUtils.rm("/tmp/test.sqlite", :force => true)
      FileUtils.cp("#{@@test_dir}/test_data/test_with_annotations.sqlite", "/tmp/test.sqlite")
      `#{@@test_dir}/../bin/core-access output -paf gene_presence_absence.txt -pac -od /tmp -db /tmp/test.sqlite`
      last_two_lines = `tail -n 2 /tmp/gene_presence_absence.txt`.split("\n")
      assert_equal "414: hypothetical protein\t0\t1", last_two_lines.first
      assert_equal "415: hypothetical protein\t1\t1", last_two_lines.last
      assert_equal 416, `wc -l /tmp/gene_presence_absence.txt`.split.first.to_i
    end
    should "output non-core presence and absence data" do
      FileUtils.rm("/tmp/test.sqlite", :force => true)
      FileUtils.cp("#{@@test_dir}/test_data/test_with_annotations.sqlite", "/tmp/test.sqlite")
      `#{@@test_dir}/../bin/core-access output -paf gene_presence_absence.txt -od /tmp -db /tmp/test.sqlite`
      last_two_lines = `tail -n 2 /tmp/gene_presence_absence.txt`.split("\n")
      assert_equal "412: hypothetical protein\t1\t0", last_two_lines.first
      assert_equal "414: hypothetical protein\t0\t1", last_two_lines.last
      assert_equal 90, `wc -l /tmp/gene_presence_absence.txt`.split.first.to_i
    end

    should "output non-merged genbank files from database" do
      FileUtils.rm("/tmp/test.sqlite", :force => true)
      FileUtils.cp("#{@@test_dir}/test_data/test_with_annotations.sqlite", "/tmp/test.sqlite")
      output = `#{@@test_dir}/../bin/core-access output -gsfl #{@@test_dir}/fasta_sequence_file_list.txt -fd #{@@test_dir} -od /tmp -db /tmp/test.sqlite`
      genbank_seq1 = rich_sequence_object_from_file("/tmp/seq1_annotated.gbk").to_biosequence
      assert_equal 384489, genbank_seq1.size
      assert_equal 388, genbank_seq1.features.select{|f| f.feature == "CDS"}.size
      genbank_seq2_multiple_entries = rich_sequence_object_from_file("/tmp/seq2_annotated.gbk")
      assert_equal 2, genbank_seq2_multiple_entries.size
      assert_equal 288354, genbank_seq2_multiple_entries.first.to_biosequence.size
      assert_equal 69638, genbank_seq2_multiple_entries.last.to_biosequence.size
      assert_equal 269, genbank_seq2_multiple_entries.first.to_biosequence.features.select{|f| f.feature == "CDS"}.size
      assert_equal 84, genbank_seq2_multiple_entries.last.to_biosequence.features.select{|f| f.feature == "CDS"}.size
    end

    should "output merged genbank files from database" do  
      FileUtils.rm("/tmp/test.sqlite", :force => true)
      FileUtils.cp("#{@@test_dir}/test_data/test_with_annotations.sqlite", "/tmp/test.sqlite")
      output = `#{@@test_dir}/../bin/core-access output -gsfl #{@@test_dir}/fasta_sequence_file_list.txt -mgc -fd #{@@test_dir} -od /tmp -db /tmp/test.sqlite`
      genbank_seq1 = rich_sequence_object_from_file("/tmp/seq1_annotated.gbk").to_biosequence
      assert_equal 384489, genbank_seq1.size
      assert_equal 388, genbank_seq1.features.select{|f| f.feature == "CDS"}.size
      genbank_seq2 = rich_sequence_object_from_file("/tmp/seq2_annotated.gbk").to_biosequence
      assert_equal 357992, genbank_seq2.size
      assert_equal 353, genbank_seq2.features.select{|f| f.feature == "CDS"}.size
    end

  end
end
