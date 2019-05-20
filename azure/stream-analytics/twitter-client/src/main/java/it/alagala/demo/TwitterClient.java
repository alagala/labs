package it.alagala.demo;

import java.io.FileNotFoundException;
import java.io.FileReader;
import java.io.IOException;
import java.util.List;
import java.util.Properties;
import java.util.concurrent.BlockingDeque;
import java.util.concurrent.LinkedBlockingDeque;

import com.google.common.collect.Lists;
import com.twitter.hbc.ClientBuilder;
import com.twitter.hbc.core.Constants;
import com.twitter.hbc.core.endpoint.StatusesFilterEndpoint;
import com.twitter.hbc.core.processor.StringDelimitedProcessor;
import com.twitter.hbc.httpclient.BasicClient;
import com.twitter.hbc.httpclient.auth.Authentication;
import com.twitter.hbc.httpclient.auth.OAuth1;

import org.apache.kafka.clients.producer.Callback;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.Producer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.clients.producer.RecordMetadata;
import org.apache.kafka.common.serialization.LongSerializer;
import org.apache.kafka.common.serialization.StringSerializer;

import twitter4j.JSONException;
import twitter4j.JSONObject;

// Basic, single-threaded Twitter client that subscribes to the tweets feed
// and publish each tweet to Azure Event Hubs, using the Kafka protocol.
//
// @author Andrea Gagliardi La Gala
//
public class TwitterClient {

    public static void run(Producer<Long, String> producer, Properties config) throws InterruptedException {

        // Create an appropriately sized blocking queue.
        //
        BlockingDeque<String> queue = new LinkedBlockingDeque<String>(10000);

        // Track terms.
        //
        final List<String> trackTerms = Lists.newArrayList(
            config.getProperty(TwitterClient.TWITTER_TRACK_TERMS).split(",")
        );
        StatusesFilterEndpoint endpoint = new StatusesFilterEndpoint();
        endpoint.addQueryParameter(Constants.LANGUAGE_PARAM, "en");
        endpoint.trackTerms(trackTerms);

        Authentication auth = new OAuth1(
            config.getProperty(TwitterClient.TWITTER_CONSUMER_KEY),
            config.getProperty(TwitterClient.TWITTER_CONSUMER_SECRET),
            config.getProperty(TwitterClient.TWITTER_TOKEN),
            config.getProperty(TwitterClient.TWITTER_SECRET)
        );

        // Create a Twitter client.
        //
        BasicClient client = new ClientBuilder()
            .name("twitter-client")
            .hosts(Constants.STREAM_HOST)
            .endpoint(endpoint)
            .authentication(auth)
            .processor(new StringDelimitedProcessor(queue))
            .build();

        // Establish a connection.
        //
        client.connect();

        // Post each tweet to Azure Event Hubs
        //
        final String topic = config.getProperty(TwitterClient.KAFKA_TOPIC);
        while (!client.isDone()) {
            try {
                JSONObject tweet = new JSONObject(queue.take());
                System.out.println(tweet.getJSONObject("user").getLong("id") + ": " + tweet.getString("text"));
                publishTweet(producer, topic, tweet);
            }
            catch (Exception e) {
                System.out.println(e);
            }
        }

        client.stop();
    }

    public static void main(String[] args) {
        try {
            TwitterClient.run(createKafkaProducer(), getAppConfig());
        }
        catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    private static void publishTweet(Producer<Long, String> producer, String topic, JSONObject tweet) throws JSONException {
        final ProducerRecord<Long, String> record = new ProducerRecord<Long,String>(
            topic, tweet.getJSONObject("user").getLong("id"), tweet.toString()
        );

        producer.send(record, new Callback() {
            @Override
            public void onCompletion(RecordMetadata metadata, Exception exception) {
                if (exception == null) {
                    System.out.println("Tweet sent to Kafka successfully: " + metadata);
                }
                else {
                    System.out.println("Error sending tweet to Kafka. Original exception: " + exception);
                }
            }
        });
    }

    private static Producer<Long, String> createKafkaProducer() {
        Properties properties = new Properties();
        try {
            properties.load(new FileReader("target/classes/producer.config"));
            properties.put(ProducerConfig.CLIENT_ID_CONFIG, "KafkaTweetsProducer");
            properties.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, LongSerializer.class.getName());
            properties.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        }
        catch (FileNotFoundException e) {
            System.out.println("Config file not found. Please provide one. Original exception: " + e);
        }
        catch (IOException e) {
            System.out.println("Error reading the config file. Original exception: " + e);
        }
        finally {
            return new KafkaProducer<>(properties);
        }
    }

    private static Properties getAppConfig() {
        Properties properties = new Properties();
        try {
            properties.load(new FileReader("target/classes/app.config"));
        }
        catch (FileNotFoundException e) {
            System.out.println("Config file not found. Please provide one. Original exception: " + e);
        }
        catch (IOException e) {
            System.out.println("Error reading the config file. Original exception: " + e);
        }
        finally {
            return properties;
        }
    }

    private static final String TWITTER_CONSUMER_KEY = "twitter.consumer.key";
    private static final String TWITTER_CONSUMER_SECRET = "twitter.consumer.secret";
    private static final String TWITTER_TOKEN = "twitter.access.token";
    private static final String TWITTER_SECRET = "twitter.access.token.secret";
    private static final String TWITTER_TRACK_TERMS = "twitter.track.terms";
    private static final String KAFKA_TOPIC = "kafka.topic";
}