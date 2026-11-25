namespace OtterDrive.AuditService.Config;

public class AwsSettings
{
    public string Region { get; set; } = "us-east-1";
    public string? EndpointUrl { get; set; }
    public string DynamoDbTable { get; set; } = "otterdrive-audit-events";
    public string S3ArchiveBucket { get; set; } = "otterdrive-audit-archive";
    public string? SnsTopicArn { get; set; }
    public int ArchiveAfterDays { get; set; } = 90;
}
