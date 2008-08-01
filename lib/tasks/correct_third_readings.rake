namespace :kiwimp do

  desc "corrects topic of third readings"
  task :correct_third_readings => :environment do
    debates = Debate.find_by_sql('select * from debates where name like "%Third Readings%";')

    contributions = debates.inject([]) do |all, debate|
      if debate.debate_topics.blank?
        all += debate.contributions.select do |contribution|
          contribution.text.include?('I move') and contribution.text.include?('be now read')
        end
      end
      all
    end

    debate_to_bills = contributions.inject({}) do |debate_bills, contribution|
      bill_text = contribution.text.match(/That the (.*)be now read/)[1].gsub('Bill and the','Bill, and the')

      bills = bill_text.split(/,( and)? the/)
      bills = bills.select { |b| b.match(/[a-z ]*(.*)/)[1].length > 0 }
      bills = bills.collect { |b| b.match(/[a-z ]*(.*)/)[1].chomp(', ') }
      debate_bills[contribution.debate] = bills
      debate_bills
    end

    debate_to_bills.each_pair { |k,v| puts k.id.to_s + " " + v.join(' ') }

    puts ''
    puts 'unknown bills:'
    debate_to_bills.each_pair do |debate, bills|
      bills.each {|name| puts debate.date.to_s + ' ' + name if Bill.find_by_bill_name(name).nil? }
    end

    debate_to_bill_ids = debate_to_bills.keys.inject({}) do |debate_bill_ids, debate|
      bills = debate_to_bills[debate].collect {|name| Bill.find_by_bill_name(name) }.compact
      debate_bill_ids[debate]= bills.collect {|b| b.id}
      debate_bill_ids
    end

    debate_to_bill_ids.each do |debate, bill_ids|
      bill_ids.each do |bill_id|
        topic = DebateTopic.find_by_debate_id_and_topic_id_and_topic_type(debate.id, bill_id, 'Bill')
        unless topic
          topic = DebateTopic.new
          topic.debate_id = debate.id
          topic.topic_type = 'Bill'
          topic.topic_id = bill_id
          topic.save
          puts topic
        end
      end
    end
  end
end
