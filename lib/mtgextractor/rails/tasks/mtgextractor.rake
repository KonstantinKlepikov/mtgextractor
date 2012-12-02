require 'mtgextractor'
require 'yaml'
require "#{Rails.root}/app/models/mtg_card"
require "#{Rails.root}/app/models/mtg_set"
require "#{Rails.root}/app/models/mtg_type"
require "#{Rails.root}/app/models/mtg_card_type"

namespace 'mtgextractor' do
  desc 'Extracts every card in every set from Gatherer and saves it to the DB'
  task :update_all_sets do
    establish_connection
    starting_set = ENV["START"]
    all_sets = MTGExtractor::SetExtractor.get_all_sets
    if starting_set && all_sets.include?(starting_set)
      puts "Processing all sets starting from #{starting_set}"
      all_sets.shift(all_sets.index(starting_set))
    end

    all_sets.each do |set|
      process_set(set)
    end
  end

  desc 'Extracts every card in provided set from Gatherer and saves it to the DB'
  task :update_set do
    establish_connection
    process_set(ENV["SET"])
  end
end

private 

def establish_connection
  environment = ENV["RAILS_ENV"] || "development"
  database_yaml = YAML::load(File.open("#{Rails.root}/config/database.yml"))[environment]
  ActiveRecord::Base.establish_connection(database_yaml)
end

def process_set(set_name)
  set = MtgSet.find_or_create_by_name(:name => set_name)

  puts "====================================="
  puts "Processing set '#{set_name}'..."
  puts "====================================="
  card_urls = MTGExtractor::SetExtractor.new(set_name).get_card_detail_urls

  card_urls.each_with_index do |url, index|
    index += 1
    extractor = MTGExtractor::CardExtractor.new(url)
    card_details = extractor.get_card_details
    html = card_details['page_html']
    create_card(card_details, set)

    # If the card is a multipart card, we need to create its other 'part' as well.
    # Because they share the same multiverse_id, we have to add the &part parameter
    # to grab its other part.
    if extractor.multipart_card?(html)
      multiverse_id = card_details['multiverse_id']
      regex = /\/Pages\/Card\/Details\.aspx\?part=([^&]+)/
      part_param = html.match(regex)[1]
      url = "#{card_details['gatherer_url']}&part=#{part_param}"
      multipart_card_data = MTGExtractor::CardExtractor.new(url).get_card_details
      create_card(multipart_card_data, set)
    end

    puts "#{index} / #{card_urls.count}: Processed card '#{card_details['name']}'"
  end

end

def card_details_hash(card_details)
  mana_cost = card_details['mana_cost'] ? card_details['mana_cost'].join(" ") : nil
  {
    :name           => card_details['name'],
    :gatherer_url   => card_details['gatherer_url'],
    :multiverse_id  => card_details['multiverse_id'],
    :image_url      => card_details['image_url'],
    :mana_cost      => mana_cost,
    :converted_cost => card_details['converted_cost'],
    :oracle_text    => card_details['oracle_text'],
    :power          => card_details['power'],
    :toughness      => card_details['toughness'],
    :loyalty        => card_details['loyalty'],
    :rarity         => card_details['rarity'],
    :transformed_id => card_details['transformed_id'],
    :colors         => card_details['colors'],
    :artist         => card_details['artist']
  }
end

def create_card(card_details, set)
  card_data = card_details_hash(card_details)
  # avoid creating duplicate cards
  return if card_already_exists?(card_data)

  # Create/find and collect types
  types = []
  type_names = card_details['types']
  type_names.each do |type|
    types << MtgType.find_or_create_by_name(type)
  end

  card = MtgCard.new(card_data)
  card.mtg_set_id = set.id
  card.mtg_types = types
  card.save
end

def card_already_exists?(card_data)
  name = card_data[:name]
  multiverse_id = card_data[:multiverse_id]
  # Because searching by oracle text has been unreliable, the only unique identifiers
  # we can use here is card name and multiverse_id. Due to the fact that multipart
  # cards have the same multiverse_id, we should only allow a maximum of 2 copies of
  # that card to exist (one for each part). Everything else will only have 1 copy in
  # the database.
  #
  # Although this isn't technically reliable either, it still works better than searching
  # by oracle text
  if name.match(/\/\//)
    # It's a multipart card. We can only allow 2 of these multiverse_ids to exist
    MtgCard.where(:name => name, :multiverse_id => multiverse_id).count == 2
  else
    # Not a multipart card, only 1 copy is allowed
    MtgCard.where(:name => name, :multiverse_id => multiverse_id).count > 0
  end
end
