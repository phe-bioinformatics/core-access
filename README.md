Core Access ReadMe
==================

Description
-----------
Core access is a suite of programs to cluster proteins from multiple genomes and allow querying of these clusters. It is specifically aimed at prokaryotes

Overview
--------
###Clustering###
This is the key process within CoreAccess. It involves taking the predicted genes in each supplied sequence and translating them to produce the putative protein sequences. These are the clustered using the greedy incremental clustering algorithm method of CD-HIT ([cdhit.org](http://cd-hit.org)). Briefly, sequences are first sorted in order of decreasing length. The longest one becomes the representative of the first cluster. Then, each remaining sequence is compared to the representatives of existing clusters. If the similarity with any representative is above a given threshold, it is grouped into that cluster. Otherwise, a new cluster is defined with that sequence as the representative.
###Database###
Once putative proteins have been clustered the information from the clusters is stored in a [Sqlite](http://www.sqlite.org) database. The schema of the database can be seen in the diagram

 ![schema](core-access/raw/master/Schema.png)

This schema allows querying of the data to find distributions of proteins amongst subsets of the strains.

Installation
------------
Core Access will run on any Unix-based machine including MacOSX. It also requires Ruby (>=1.8.7 and easily installed by most systems package manager e.g yum or apt or via [Ruby Version Manager RVM](https://rvm.io)), [Sqlite3](http://www.sqlite.org/), [CD-HIT](http://weizhong-lab.ucsd.edu/cd-hit) and in most cases [Glimmer3](http://www.cbcb.umd.edu/software/glimmer) will also be needed.  
If these requirements are met then installation of Core Access is as simple as running the command  
 `gem install core-access`  
This uses the Ruby package manager, Rubygems, to install the program and all it's dependencies.

Running Core-Access
-------------------
Core Access can be run using one of several commands. These are

*  create (the key command to cluster proteins and create the database that records the clustering information)
*  annotate (annotate the clusters in the database using blast)
*  search (query the database for information such as core genes and genes unique to a subset of strains)
*  output (produce output from the database such as a presence and absence matrix or annotated genbank files)
*  readme (produce read me information for each command including options)

Options for each command can either be given as arguments e.g -od /path/to/a/directory or --output_directory /path/to/a/directory or in a config file in YAML format (full option names required) e.g
    output_dir: /path/to/a/directory
    sequence_file_list: fasta_sequence_file_list.txt

All commands require two essential options

*  `-db/--database` The path to the sqlite database that will either be created or accessed
*  `-od/--output_dir` The path to the output directory where files will be created as part of the process

###Create###
This command will take all sequences supplied (usually genomic sequences) and generate putative proteins from them. If the sequence file supplied is in a rich sequence format such as GenBank or EMBL then the CDS features within these files will be used to specify the genes, otherwise if supplied in fasta format the genes will be predicted using [Glimmer3](http://www.cbcb.umd.edu/software/glimmer). Therefore if you are supplying unannotated sequence in fasta format you will need to install Glimmer3.

